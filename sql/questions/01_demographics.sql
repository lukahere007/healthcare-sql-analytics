-- title: Living population by age band and sex (with subtotals)
-- grain: age_band, gender
-- rate_columns: pct_of_population, pct_female
--
-- Question
--   Who is in the population on the as-of date? Age/sex mix, with subtotals.
--
-- Technique
--   GROUPING SETS gives the detail rows, the per-age-band subtotals, the per-sex
--   subtotals and the grand total in one pass; GROUPING() labels the rolled-up
--   rows. A window SUM over the grand-total row turns counts into shares.
--   Deceased patients are excluded (alive_at_as_of).

WITH living AS (
    SELECT patient_id, gender, age_at_as_of, age_band_at_as_of AS age_band
    FROM int_patients
    WHERE alive_at_as_of
),
agg AS (
    SELECT
        CASE WHEN GROUPING(age_band) = 1 THEN 'All ages' ELSE age_band END AS age_band,
        CASE WHEN GROUPING(gender)   = 1 THEN 'All'      ELSE gender   END AS gender,
        GROUPING(age_band) + GROUPING(gender)                               AS rollup_level,
        COUNT(*)                                                            AS patients,
        ROUND(MEDIAN(age_at_as_of), 1)                                      AS median_age,
        COUNT(*) FILTER (WHERE gender = 'F')                                AS female_patients
    FROM living
    GROUP BY GROUPING SETS ((age_band, gender), (age_band), (gender), ())
)
SELECT
    age_band,
    gender,
    patients,
    median_age,
    ROUND(patients / MAX(patients) FILTER (WHERE rollup_level = 2) OVER (), 4) AS pct_of_population,
    ROUND(female_patients / patients, 4)                                       AS pct_female
FROM agg
ORDER BY age_band = 'All ages', age_band, gender = 'All', gender;
