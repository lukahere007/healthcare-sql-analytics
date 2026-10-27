-- title: Dates are internally consistent
-- severity: error

WITH rules AS (
    SELECT 'patients: death_date >= birth_date' AS rule, COUNT(*) AS failing_rows
    FROM stg_patients WHERE death_date < birth_date
    UNION ALL
    SELECT 'encounters: stop_ts >= start_ts', COUNT(*)
    FROM stg_encounters WHERE stop_ts < start_ts
    UNION ALL
    SELECT 'encounters: not before birth', COUNT(*)
    FROM stg_encounters AS e JOIN stg_patients AS p USING (patient_id)
    WHERE CAST(e.start_ts AS DATE) < p.birth_date
    UNION ALL
    -- Synthea records an administrative "Death Certification" visit after death;
    -- any *clinical* encounter after death would be an error.
    SELECT 'encounters: no clinical encounter after death', COUNT(*)
    FROM stg_encounters AS e JOIN stg_patients AS p USING (patient_id)
    WHERE CAST(e.start_ts AS DATE) > p.death_date
      AND e.encounter_description <> 'Death Certification'
    UNION ALL
    SELECT 'conditions: resolved_date >= onset_date', COUNT(*)
    FROM stg_conditions WHERE resolved_date < onset_date
    UNION ALL
    SELECT 'nothing dated after the as-of date', COUNT(*)
    FROM stg_encounters CROSS JOIN params
    WHERE CAST(start_ts AS DATE) > as_of_date
    UNION ALL
    SELECT 'inpatient stays do not overlap after merging', COUNT(*)
    FROM (SELECT admit_ts, LAG(discharge_ts) OVER (PARTITION BY patient_id ORDER BY admit_ts) AS prev_discharge
          FROM int_inpatient_stays)
    WHERE admit_ts <= prev_discharge
)
SELECT rule, failing_rows FROM rules WHERE failing_rows > 0;
