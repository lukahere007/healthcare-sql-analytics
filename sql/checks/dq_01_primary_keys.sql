-- title: Primary keys are unique and not null
-- severity: error
--
-- Each check returns one row per violated rule (empty result = pass).

WITH rules AS (
    SELECT 'patients.patient_id unique' AS rule,
           COUNT(*) - COUNT(DISTINCT patient_id) AS failing_rows FROM stg_patients
    UNION ALL
    SELECT 'patients.patient_id not null', COUNT(*) FILTER (WHERE patient_id IS NULL) FROM stg_patients
    UNION ALL
    SELECT 'encounters.encounter_id unique', COUNT(*) - COUNT(DISTINCT encounter_id) FROM stg_encounters
    UNION ALL
    SELECT 'encounters.encounter_id not null', COUNT(*) FILTER (WHERE encounter_id IS NULL) FROM stg_encounters
    UNION ALL
    SELECT 'payers.payer_id unique', COUNT(*) - COUNT(DISTINCT payer_id) FROM stg_payers
    UNION ALL
    SELECT 'int_inpatient_stays.stay_id unique', COUNT(*) - COUNT(DISTINCT stay_id) FROM int_inpatient_stays
    UNION ALL
    SELECT 'int_patient_conditions (patient, group) unique',
           COUNT(*) - COUNT(DISTINCT (patient_id, condition_group)) FROM int_patient_conditions
)
SELECT rule, failing_rows FROM rules WHERE failing_rows > 0;
