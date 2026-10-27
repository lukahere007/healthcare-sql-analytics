-- title: Known source-data defects and implausible values (warnings)
-- severity: warn
--
-- These are real quirks of the Synthea output. They do not stop the pipeline;
-- they are reported in results/data_quality.csv and handled where they matter
-- (e.g. int_medication_episodes drops prescriptions that stop before they start).

WITH rules AS (
    SELECT 'medications: stop_ts before start_ts (dropped from episodes)' AS rule, COUNT(*) AS failing_rows
    FROM stg_medications WHERE stop_ts < start_ts
    UNION ALL
    SELECT 'observations: HbA1c < 4% (physiologically implausible)', COUNT(*)
    FROM stg_observations WHERE loinc_code = '4548-4' AND value_numeric < 4
    UNION ALL
    SELECT 'observations: HbA1c > 20%', COUNT(*)
    FROM stg_observations WHERE loinc_code = '4548-4' AND value_numeric > 20
    UNION ALL
    SELECT 'observations: BMI outside 10-80', COUNT(*)
    FROM stg_observations WHERE loinc_code = '39156-5' AND value_numeric NOT BETWEEN 10 AND 80
    UNION ALL
    SELECT 'medications: single record costing > $1M', COUNT(*)
    FROM stg_medications WHERE total_cost > 1000000
    UNION ALL
    SELECT 'encounters: administrative Death Certification after death', COUNT(*)
    FROM stg_encounters AS e JOIN stg_patients AS p USING (patient_id)
    WHERE CAST(e.start_ts AS DATE) > p.death_date
)
SELECT rule, failing_rows FROM rules WHERE failing_rows > 0;
