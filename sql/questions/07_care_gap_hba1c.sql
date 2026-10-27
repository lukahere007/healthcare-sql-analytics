-- title: Care gap - adults with type 2 diabetes and no HbA1c test in the last 12 months
-- grain: age_band
-- rate_columns: care_gap_rate, poor_control_rate_among_tested, implausible_low_rate_among_tested
--
-- Question
--   Which living adult diabetics have not had an HbA1c (LOINC 4548-4) in the
--   12 months up to the as-of date? Among those tested, how many are poorly
--   controlled (last HbA1c > 9%, the HEDIS "poor control" cut-off)?
--
-- Definitions
--   Denominator : alive on the as-of date, age 18-75 (the HEDIS diabetes-care
--                 age range), type 2 diabetes group active on the as-of date.
--   Gap         : NOT EXISTS an HbA1c result in (as_of - 12 months, as_of].
--   Last value  : most recent HbA1c in the window (ROW_NUMBER via QUALIFY).
--   Plausibility: an HbA1c below 4% is physiologically implausible for a
--                 diabetic; we report how often Synthea produces one, because a
--                 number that looks like "excellent control" is really a
--                 simulator artefact (see README).
--
-- Technique
--   Anti-join with NOT EXISTS (NULL-safe, unlike NOT IN), QUALIFY to pick the
--   latest result per patient without a self-join, GROUPING SETS for totals.

WITH diabetics AS (
    SELECT p.patient_id, p.age_band_at_as_of AS age_band
    FROM int_patients AS p
    JOIN int_patient_conditions AS c
      ON c.patient_id = p.patient_id
     AND c.condition_group = 'Type 2 diabetes'
     AND c.active_at_as_of
    WHERE p.alive_at_as_of
      AND p.age_at_as_of BETWEEN 18 AND 75
),
hba1c_window AS (
    SELECT o.*
    FROM stg_observations AS o
    CROSS JOIN params AS prm
    WHERE o.loinc_code = '4548-4'
      AND o.observation_ts >  CAST(prm.as_of_date - INTERVAL 12 MONTH AS TIMESTAMP)
      AND o.observation_ts <= CAST(prm.as_of_date + INTERVAL 1 DAY AS TIMESTAMP)
),
last_hba1c AS (
    SELECT patient_id, value_numeric AS last_hba1c, observation_ts AS last_hba1c_ts
    FROM hba1c_window
    QUALIFY ROW_NUMBER() OVER (PARTITION BY patient_id ORDER BY observation_ts DESC) = 1
),
flagged AS (
    SELECT
        d.patient_id,
        d.age_band,
        NOT EXISTS (SELECT 1 FROM hba1c_window AS h WHERE h.patient_id = d.patient_id) AS has_gap,
        l.last_hba1c
    FROM diabetics AS d
    LEFT JOIN last_hba1c AS l USING (patient_id)
)
SELECT
    CASE WHEN GROUPING(age_band) = 1 THEN '18-75 (all)' ELSE age_band END   AS age_band,
    COUNT(*)                                                               AS diabetics,
    COUNT(*) FILTER (WHERE has_gap)                                        AS without_hba1c_12m,
    ROUND(COUNT(*) FILTER (WHERE has_gap) / COUNT(*), 4)                   AS care_gap_rate,
    ROUND(MEDIAN(last_hba1c), 2)                                           AS median_last_hba1c,
    ROUND(COUNT(*) FILTER (WHERE last_hba1c > 9)
          / NULLIF(COUNT(*) FILTER (WHERE NOT has_gap), 0), 4)             AS poor_control_rate_among_tested,
    ROUND(COUNT(*) FILTER (WHERE last_hba1c < 4)
          / NULLIF(COUNT(*) FILTER (WHERE NOT has_gap), 0), 4)             AS implausible_low_rate_among_tested
FROM flagged
GROUP BY GROUPING SETS ((age_band), ())
ORDER BY GROUPING(age_band), age_band;
