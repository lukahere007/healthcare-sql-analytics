-- title: Top cost drivers per patient-year (study window)
-- grain: cost_rank
-- rate_columns: share_of_total_cost, cumulative_share
--
-- Question
--   Where does the money go? Which clinical reasons and drugs account for most
--   of the cost, expressed per patient-year of observation?
--
-- Definitions
--   Cost sources (study window, by service date):
--     * encounters  : TOTAL_CLAIM_COST (encounter + its procedures, labs, etc.);
--                     driver = the encounter's reason, else its description
--     * medications : TOTALCOST of each prescription record, attributed to its
--                     start date; driver = drug description
--   Patient-years = sum over patients of the overlap between
--   [study_start, as_of_date] and [birth_date, death_date or as_of_date].
--
-- Technique
--   UNION ALL of two cost streams, date-range overlap arithmetic with
--   GREATEST/LEAST, RANK() + QUALIFY to keep the top 15, a running-total window
--   for the cumulative share (Pareto view).

WITH person_time AS (
    SELECT
        SUM(GREATEST(
                DATE_DIFF('day',
                          GREATEST(p.birth_date, prm.study_start),
                          LEAST(COALESCE(p.death_date, prm.as_of_date), prm.as_of_date)),
                0)) / 365.25 AS patient_years
    FROM stg_patients AS p
    CROSS JOIN params AS prm
),
costs AS (
    SELECT
        'Encounter: ' || e.encounter_class                              AS cost_category,
        COALESCE(e.reason_description, e.encounter_description)          AS driver,
        e.total_claim_cost                                               AS cost
    FROM stg_encounters AS e
    CROSS JOIN params AS prm
    WHERE CAST(e.start_ts AS DATE) BETWEEN prm.study_start AND prm.as_of_date

    UNION ALL

    SELECT
        'Medication'                                                    AS cost_category,
        m.medication_description                                         AS driver,
        m.total_cost                                                     AS cost
    FROM stg_medications AS m
    CROSS JOIN params AS prm
    WHERE CAST(m.start_ts AS DATE) BETWEEN prm.study_start AND prm.as_of_date
),
by_driver AS (
    SELECT
        cost_category,
        driver,
        SUM(cost)                                       AS total_cost,
        COUNT(*)                                        AS n_records,
        SUM(SUM(cost)) OVER ()                          AS grand_total_cost
    FROM costs
    GROUP BY cost_category, driver
    QUALIFY RANK() OVER (ORDER BY SUM(cost) DESC) <= 15
)
SELECT
    RANK() OVER (ORDER BY b.total_cost DESC)                                  AS cost_rank,
    b.cost_category,
    b.driver,
    b.n_records,
    ROUND(b.total_cost, 0)                                                    AS total_cost,
    ROUND(b.total_cost / pt.patient_years, 2)                                 AS cost_per_patient_year,
    ROUND(b.total_cost / b.grand_total_cost, 4)                               AS share_of_total_cost,
    ROUND(SUM(b.total_cost) OVER (ORDER BY b.total_cost DESC
                                  ROWS UNBOUNDED PRECEDING) / b.grand_total_cost, 4) AS cumulative_share,
    ROUND(b.grand_total_cost / pt.patient_years, 2)                           AS all_cost_per_patient_year
FROM by_driver AS b
CROSS JOIN person_time AS pt
ORDER BY cost_rank;
