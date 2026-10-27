-- title: Required fields are present and parse to the right type
-- severity: error
--
-- A NULL in a staged column whose raw value was NOT NULL means the cast in
-- 01_staging.sql failed (TRY_CAST / TRY_STRPTIME return NULL instead of
-- raising), so these rules catch both missing values and format drift.

WITH rules AS (
    SELECT 'patients.birth_date parsed' AS rule, COUNT(*) AS failing_rows
    FROM stg_patients WHERE birth_date IS NULL
    UNION ALL
    SELECT 'patients.death_date parsed when present', COUNT(*)
    FROM raw_patients WHERE DEATHDATE IS NOT NULL AND TRY_CAST(DEATHDATE AS DATE) IS NULL
    UNION ALL
    SELECT 'patients.gender in (M, F)', COUNT(*)
    FROM stg_patients WHERE gender NOT IN ('M', 'F') OR gender IS NULL
    UNION ALL
    SELECT 'encounters.start_ts / stop_ts parsed', COUNT(*)
    FROM stg_encounters WHERE start_ts IS NULL OR stop_ts IS NULL
    UNION ALL
    SELECT 'encounters.total_claim_cost parsed', COUNT(*)
    FROM stg_encounters WHERE total_claim_cost IS NULL
    UNION ALL
    SELECT 'conditions.onset_date parsed', COUNT(*)
    FROM stg_conditions WHERE onset_date IS NULL
    UNION ALL
    SELECT 'medications.start_ts parsed', COUNT(*)
    FROM stg_medications WHERE start_ts IS NULL
    UNION ALL
    SELECT 'medications.stop_ts parsed when present', COUNT(*)
    FROM raw_medications WHERE STOP IS NOT NULL AND parse_ts(STOP) IS NULL
    UNION ALL
    SELECT 'observations: numeric LOINC codes have a numeric value', COUNT(*)
    FROM stg_observations
    WHERE loinc_code <> '72166-2'            -- smoking status is a coded text answer
      AND value_numeric IS NULL
)
SELECT rule, failing_rows FROM rules WHERE failing_rows > 0;
