-- title: Monthly encounter volume by setting, with month-on-month, year-on-year and rolling trends
-- grain: month
--
-- Question
--   How has encounter volume moved over the study window, by care setting?
--
-- Definitions
--   Months from the first full month of the study window to the last full
--   month before the as-of date. Encounters counted in the month they start.
--
-- Technique
--   A calendar spine from GENERATE_SERIES (so a month with no encounters shows
--   0 instead of disappearing), conditional aggregation to pivot the settings,
--   LAG(1) / LAG(12) for month-on-month and year-on-year change, and a
--   12-month moving average with an explicit ROWS frame.

WITH bounds AS (
    SELECT DATE_TRUNC('month', study_start)                   AS first_month,
           DATE_TRUNC('month', as_of_date) - INTERVAL 1 MONTH AS last_month
    FROM params
),
spine AS (
    SELECT CAST(m AS DATE) AS month
    FROM bounds, GENERATE_SERIES(first_month, last_month, INTERVAL 1 MONTH) AS g(m)
),
monthly AS (
    SELECT
        s.month,
        COUNT(e.encounter_id)                                                      AS total,
        COUNT(e.encounter_id) FILTER (WHERE e.encounter_class = 'wellness')        AS wellness,
        COUNT(e.encounter_id) FILTER (WHERE e.encounter_class = 'ambulatory')      AS ambulatory,
        COUNT(e.encounter_id) FILTER (WHERE e.encounter_class = 'outpatient')      AS outpatient,
        COUNT(e.encounter_id) FILTER (WHERE e.encounter_class = 'urgentcare')      AS urgent_care,
        COUNT(e.encounter_id) FILTER (WHERE e.encounter_class = 'emergency')       AS emergency,
        COUNT(e.encounter_id) FILTER (WHERE e.encounter_class = 'inpatient')       AS inpatient,
        COUNT(e.encounter_id) FILTER (WHERE e.encounter_class = 'virtual')         AS virtual,
        COUNT(e.encounter_id) FILTER (WHERE e.encounter_class NOT IN
              ('wellness','ambulatory','outpatient','urgentcare','emergency','inpatient','virtual'))
                                                                                   AS other
    FROM spine AS s
    LEFT JOIN stg_encounters AS e
           ON DATE_TRUNC('month', e.start_ts) = s.month
    GROUP BY s.month
)
SELECT
    month,
    total, wellness, ambulatory, outpatient, urgent_care, emergency, inpatient, virtual, other,
    total - LAG(total) OVER (ORDER BY month)                                     AS mom_change,
    ROUND(total / NULLIF(LAG(total, 12) OVER (ORDER BY month), 0) - 1, 4)        AS yoy_pct_change,
    ROUND(AVG(total) OVER (ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW), 1)
                                                                                 AS rolling_12m_avg,
    SUM(total) OVER (PARTITION BY YEAR(month) ORDER BY month)                    AS ytd_total
FROM monthly
ORDER BY month;
