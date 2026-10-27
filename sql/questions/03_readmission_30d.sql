-- title: 30-day readmission rate, overall and by principal reason of the index stay
-- grain: principal_reason
-- rate_columns: all_cause_readmission_rate, unplanned_readmission_rate
--
-- Question
--   Of adult patients discharged alive from hospital, what share are admitted
--   again within 30 days? Which admission reasons drive it?
--
-- Definitions (written out because "readmission rate" means nothing without them)
--   Stay             : inpatient encounters merged into hospital stays
--                      (int_inpatient_stays; overlapping encounters = transfers,
--                      so they are one stay, never a readmission).
--   Index stay       : a stay that
--                        1. ends (discharge_date) inside the study window and at
--                           least 30 days before the as-of date (full follow-up);
--                        2. belongs to a patient aged >= 18 at admission;
--                        3. does not end in death (death_date > discharge_date).
--                      A stay can be both a readmission and an index stay
--                      (as in the CMS measures).
--   Readmission      : the patient's NEXT stay (LEAD) if it starts after the
--                      index discharge and within 30 days of the discharge date.
--   Unplanned        : the readmission's principal reason is not in
--                      ref_planned_admission_reasons (hand-curated, modelled on
--                      the CMS Planned Readmission Algorithm: chemotherapy,
--                      transplant, elective procedures). As in CMS, only the
--                      first readmission is examined.
--
-- Output: one row for all index stays + one per principal reason with >= 20
-- index stays (smaller reasons pooled), via GROUPING SETS.

WITH stays AS (
    SELECT
        s.*,
        p.birth_date,
        p.death_date,
        LEAD(s.admit_ts)         OVER w AS next_admit_ts,
        LEAD(s.principal_reason) OVER w AS next_principal_reason
    FROM int_inpatient_stays AS s
    JOIN stg_patients        AS p USING (patient_id)
    WINDOW w AS (PARTITION BY s.patient_id ORDER BY s.admit_ts)
),
index_stays AS (
    SELECT
        s.*,
        COALESCE(s.next_admit_ts > s.discharge_ts
                 AND CAST(s.next_admit_ts AS DATE) <= s.discharge_date + INTERVAL 30 DAY,
                 FALSE) AS is_readmitted
    FROM stays AS s
    CROSS JOIN params AS prm
    WHERE s.discharge_date >= prm.study_start
      AND s.discharge_date <= prm.as_of_date - INTERVAL 30 DAY        -- full follow-up
      AND age_years(s.birth_date, s.admit_date) >= 18                 -- adults
      AND (s.death_date IS NULL OR s.death_date > s.discharge_date)   -- discharged alive
),
classified AS (
    SELECT
        i.*,
        i.is_readmitted AND pr.principal_reason IS NULL AS is_unplanned_readmission,
        -- pool small reason groups so rates are not computed on 3 stays
        CASE WHEN COUNT(*) OVER (PARTITION BY i.principal_reason) >= 20
             THEN i.principal_reason
             ELSE 'Other reasons (< 20 index stays each)'
        END AS reason_group
    FROM index_stays AS i
    LEFT JOIN ref_planned_admission_reasons AS pr
           ON pr.principal_reason = i.next_principal_reason
)
SELECT
    CASE WHEN GROUPING(reason_group) = 1 THEN 'ALL INDEX STAYS' ELSE reason_group END AS principal_reason,
    COUNT(*)                                                       AS index_stays,
    COUNT(DISTINCT patient_id)                                     AS patients,
    COUNT(*) FILTER (WHERE is_readmitted)                          AS readmissions_all_cause,
    COUNT(*) FILTER (WHERE is_unplanned_readmission)               AS readmissions_unplanned,
    ROUND(AVG(CASE WHEN is_readmitted THEN 1 ELSE 0 END), 4)            AS all_cause_readmission_rate,
    ROUND(AVG(CASE WHEN is_unplanned_readmission THEN 1 ELSE 0 END), 4) AS unplanned_readmission_rate
FROM classified
GROUP BY GROUPING SETS ((), (reason_group))
ORDER BY GROUPING(reason_group) DESC, index_stays DESC, principal_reason;
