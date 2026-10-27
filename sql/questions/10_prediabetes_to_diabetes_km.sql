-- title: Time from prediabetes to type 2 diabetes (Kaplan-Meier, censored at death / as-of date)
-- grain: years_since_prediabetes
-- rate_columns: survival_free_of_diabetes, cumulative_incidence
--
-- Question
--   After a prediabetes diagnosis, how quickly do patients progress to type 2
--   diabetes? Simple "% who progressed" is biased because follow-up differs
--   (someone diagnosed last year has had no time to progress), so we estimate
--   a Kaplan-Meier curve with censoring.
--
-- Definitions
--   Origin   : first prediabetes onset date.
--   Event    : first onset of any code in the 'Type 2 diabetes' group after
--              the origin. Patients whose diabetes was recorded on/before the
--              prediabetes date are excluded (not at risk).
--   Censoring: death or the as-of date, whichever comes first.
--   Note     : conditions keep their full history in Synthea (unlike
--              encounters), so origins before study_start are allowed.
--
-- Technique
--   Product-limit estimator in pure SQL:
--     n_at_risk(t) = subjects with follow-up >= t   (reverse running SUM)
--     S(t)         = PRODUCT over event times <= t of (1 - d/n)
--   computed as EXP(SUM(LN(1 - d/n))) over an ordered window. An ASOF JOIN then
--   reads the step function at whole-year landmarks.

WITH origin AS (
    SELECT patient_id, first_onset_date AS origin_date
    FROM int_patient_conditions
    WHERE condition_group = 'Prediabetes'
),
diabetes AS (
    SELECT patient_id, first_onset_date AS dm_date
    FROM int_patient_conditions
    WHERE condition_group = 'Type 2 diabetes'
),
subjects AS (
    SELECT
        o.patient_id,
        o.origin_date,
        LEAST(COALESCE(p.death_date, prm.as_of_date), prm.as_of_date) AS censor_date,
        d.dm_date
    FROM origin AS o
    JOIN stg_patients AS p USING (patient_id)
    LEFT JOIN diabetes AS d USING (patient_id)
    CROSS JOIN params AS prm
    WHERE d.dm_date IS NULL OR d.dm_date > o.origin_date     -- at risk at origin
),
follow_up AS (
    SELECT
        patient_id,
        (dm_date IS NOT NULL AND dm_date <= censor_date)                 AS had_event,
        DATE_DIFF('day', origin_date,
                  CASE WHEN dm_date IS NOT NULL AND dm_date <= censor_date
                       THEN dm_date ELSE censor_date END) / 365.25        AS t_years
    FROM subjects
),
by_time AS (            -- one row per distinct follow-up time
    SELECT
        t_years,
        COUNT(*) FILTER (WHERE had_event)     AS events,
        COUNT(*)                              AS leaving       -- events + censored
    FROM follow_up
    GROUP BY t_years
),
km AS (
    SELECT
        t_years,
        events,
        SUM(leaving) OVER (ORDER BY t_years DESC ROWS UNBOUNDED PRECEDING) AS n_at_risk
    FROM by_time
),
curve AS (
    SELECT
        t_years,
        n_at_risk,
        SUM(events) OVER (ORDER BY t_years ROWS UNBOUNDED PRECEDING) AS cum_events,
        -- product-limit: exp of a running sum of logs. GREATEST guards ln(0)
        -- (only possible if everyone left at risk has the event at once).
        EXP(SUM(LN(GREATEST(1 - events / n_at_risk, 1e-12)))
            OVER (ORDER BY t_years ROWS UNBOUNDED PRECEDING))             AS survival
    FROM km
),
landmarks AS (
    SELECT CAST(y AS DOUBLE) AS years_since_prediabetes
    FROM GENERATE_SERIES(0, 30, 1) AS g(y)
)
SELECT
    CAST(l.years_since_prediabetes AS INTEGER)            AS years_since_prediabetes,
    (SELECT COUNT(*) FROM follow_up AS f
      WHERE f.t_years > l.years_since_prediabetes)        AS n_still_at_risk,
    CAST(COALESCE(c.cum_events, 0) AS INTEGER)            AS cumulative_events,
    ROUND(COALESCE(c.survival, 1.0), 4)                   AS survival_free_of_diabetes,
    ROUND(1 - COALESCE(c.survival, 1.0), 4)               AS cumulative_incidence,
    (SELECT COUNT(*) FROM follow_up)                      AS cohort_size
FROM landmarks AS l
ASOF LEFT JOIN curve AS c
    ON l.years_since_prediabetes >= c.t_years
ORDER BY years_since_prediabetes;
