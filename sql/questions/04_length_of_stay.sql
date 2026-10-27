-- title: Length-of-stay distribution, overall and by principal reason
-- grain: principal_reason
-- rate_columns: pct_los_0_or_1, pct_long_stay_7plus
--
-- Question
--   How long do hospital stays last, and which admission reasons have the
--   longest stays?
--
-- Definitions
--   Stays from int_inpatient_stays (transfers merged), discharged inside the
--   study window. LOS = midnight count (discharge date - admit date), so a
--   same-day stay has LOS 0. Reasons with < 10 stays are pooled.
--
-- Technique
--   Ordered-set aggregates (QUANTILE_CONT) for the percentiles, FILTER for the
--   share of short (0-1 day) and long (7+ day) stays, GROUPING SETS for the overall row.

WITH stays AS (
    SELECT
        s.*,
        CASE WHEN COUNT(*) OVER (PARTITION BY s.principal_reason) >= 10
             THEN s.principal_reason
             ELSE 'Other reasons (< 10 stays each)'
        END AS reason_group
    FROM int_inpatient_stays AS s
    CROSS JOIN params AS prm
    WHERE s.discharge_date BETWEEN prm.study_start AND prm.as_of_date
)
SELECT
    CASE WHEN GROUPING(reason_group) = 1 THEN 'ALL STAYS' ELSE reason_group END AS principal_reason,
    COUNT(*)                                                    AS stays,
    ROUND(AVG(los_days), 2)                                     AS mean_los,
    QUANTILE_CONT(los_days, 0.25)                               AS p25_los,
    QUANTILE_CONT(los_days, 0.50)                               AS median_los,
    QUANTILE_CONT(los_days, 0.75)                               AS p75_los,
    QUANTILE_CONT(los_days, 0.90)                               AS p90_los,
    MAX(los_days)                                               AS max_los,
    ROUND(COUNT(*) FILTER (WHERE los_days <= 1) / COUNT(*), 4)  AS pct_los_0_or_1,
    ROUND(COUNT(*) FILTER (WHERE los_days >= 7) / COUNT(*), 4)  AS pct_long_stay_7plus,
    SUM(los_days)                                               AS total_bed_days
FROM stays
GROUP BY GROUPING SETS ((), (reason_group))
ORDER BY GROUPING(reason_group) DESC, mean_los DESC, principal_reason;
