-- title: Referential integrity - no orphan foreign keys
-- severity: error
--
-- Anti-joins (NOT EXISTS) from each child table to its parent.

WITH rules AS (
    SELECT 'encounters.patient_id -> patients' AS rule, COUNT(*) AS failing_rows
    FROM stg_encounters AS c
    WHERE NOT EXISTS (SELECT 1 FROM stg_patients AS p WHERE p.patient_id = c.patient_id)
    UNION ALL
    SELECT 'encounters.payer_id -> payers', COUNT(*)
    FROM stg_encounters AS c
    WHERE NOT EXISTS (SELECT 1 FROM stg_payers AS p WHERE p.payer_id = c.payer_id)
    UNION ALL
    SELECT 'conditions.patient_id -> patients', COUNT(*)
    FROM stg_conditions AS c
    WHERE NOT EXISTS (SELECT 1 FROM stg_patients AS p WHERE p.patient_id = c.patient_id)
    UNION ALL
    SELECT 'conditions.encounter_id -> encounters', COUNT(*)
    FROM stg_conditions AS c
    WHERE NOT EXISTS (SELECT 1 FROM stg_encounters AS e WHERE e.encounter_id = c.encounter_id)
    UNION ALL
    SELECT 'medications.encounter_id -> encounters', COUNT(*)
    FROM stg_medications AS c
    WHERE NOT EXISTS (SELECT 1 FROM stg_encounters AS e WHERE e.encounter_id = c.encounter_id)
    UNION ALL
    SELECT 'medications: patient matches its encounter', COUNT(*)
    FROM stg_medications AS m
    JOIN stg_encounters AS e USING (encounter_id)
    WHERE m.patient_id <> e.patient_id
    UNION ALL
    SELECT 'observations.encounter_id -> encounters', COUNT(*)
    FROM stg_observations AS c
    WHERE c.encounter_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM stg_encounters AS e WHERE e.encounter_id = c.encounter_id)
    UNION ALL
    SELECT 'condition codes used in ref_condition_groups exist in the data', COUNT(*)
    FROM ref_condition_groups AS g
    WHERE NOT EXISTS (SELECT 1 FROM stg_conditions AS c WHERE c.condition_code = g.snomed_code)
)
SELECT rule, failing_rows FROM rules WHERE failing_rows > 0;
