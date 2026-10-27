-- title: Prevalence of chronic conditions by age band (living patients, as-of date)
-- grain: condition_group
-- rate_columns: prevalence_all, prev_0_17, prev_18_39, prev_40_64, prev_65_74, prev_75_84, prev_85_plus
--
-- Question
--   On the as-of date, what share of living patients in each age band has an
--   active chronic condition?
--
-- Definitions
--   Condition groups come from the hand-curated ref_condition_groups (SNOMED
--   code -> group). "Active" = onset on/before the as-of date and not resolved
--   by then (int_patient_conditions.active_at_as_of).
--   Denominator = all living patients in the band, with or without conditions.
--
-- Technique
--   Conditional aggregation (COUNT ... FILTER) pivots age bands into columns;
--   the denominators come from a separate CTE pivoted the same way and
--   CROSS JOINed, so a band with zero cases still gets a 0 (not a missing row).

WITH living AS (
    SELECT patient_id, age_band_at_as_of AS age_band
    FROM int_patients
    WHERE alive_at_as_of
),
denominators AS (
    SELECT
        COUNT(*)                                       AS n_all,
        COUNT(*) FILTER (WHERE age_band = '0-17')      AS n_0_17,
        COUNT(*) FILTER (WHERE age_band = '18-39')     AS n_18_39,
        COUNT(*) FILTER (WHERE age_band = '40-64')     AS n_40_64,
        COUNT(*) FILTER (WHERE age_band = '65-74')     AS n_65_74,
        COUNT(*) FILTER (WHERE age_band = '75-84')     AS n_75_84,
        COUNT(*) FILTER (WHERE age_band = '85+')       AS n_85_plus
    FROM living
),
cases AS (
    SELECT
        c.condition_group,
        COUNT(*)                                       AS c_all,
        COUNT(*) FILTER (WHERE l.age_band = '0-17')    AS c_0_17,
        COUNT(*) FILTER (WHERE l.age_band = '18-39')   AS c_18_39,
        COUNT(*) FILTER (WHERE l.age_band = '40-64')   AS c_40_64,
        COUNT(*) FILTER (WHERE l.age_band = '65-74')   AS c_65_74,
        COUNT(*) FILTER (WHERE l.age_band = '75-84')   AS c_75_84,
        COUNT(*) FILTER (WHERE l.age_band = '85+')     AS c_85_plus
    FROM int_patient_conditions AS c          -- one row per patient x group
    JOIN living AS l USING (patient_id)
    WHERE c.active_at_as_of
    GROUP BY c.condition_group
)
SELECT
    c.condition_group,
    c.c_all                                     AS patients_with_condition,
    ROUND(c.c_all     / d.n_all,     4)         AS prevalence_all,
    ROUND(c.c_0_17    / d.n_0_17,    4)         AS prev_0_17,
    ROUND(c.c_18_39   / d.n_18_39,   4)         AS prev_18_39,
    ROUND(c.c_40_64   / d.n_40_64,   4)         AS prev_40_64,
    ROUND(c.c_65_74   / d.n_65_74,   4)         AS prev_65_74,
    ROUND(c.c_75_84   / d.n_75_84,   4)         AS prev_75_84,
    ROUND(c.c_85_plus / d.n_85_plus, 4)         AS prev_85_plus
FROM cases AS c
CROSS JOIN denominators AS d
ORDER BY prevalence_all DESC, condition_group;
