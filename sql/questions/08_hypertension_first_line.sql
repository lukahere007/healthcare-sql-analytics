-- title: First-line treatment pathways for newly diagnosed hypertension
-- grain: first_line_regimen
-- rate_columns: share_of_cohort, escalation_rate
--
-- Question
--   For patients newly diagnosed with essential hypertension, what is the first
--   antihypertensive regimen, how quickly is it started, and how often is a
--   drug from another class added later?
--
-- Definitions
--   Cohort        : first hypertension diagnosis (int_patient_conditions) on or
--                   after study_start and at least 365 days before the as-of
--                   date (so everyone has a full year to start treatment).
--                   Incident cases only - earlier diagnoses would have their
--                   first prescription outside the recorded history.
--   First line    : every antihypertensive class (ref_antihypertensives,
--                   hand-curated) started on the first treatment day within
--                   365 days of diagnosis; two classes on that day = combination.
--   Escalation    : a further class first started after the first-line day.
--
-- Technique
--   DENSE_RANK over start dates picks *all* drugs started on the first
--   treatment day (ROW_NUMBER would silently drop combination therapy),
--   STRING_AGG(DISTINCT ... ORDER BY) builds a canonical regimen label, and an
--   outer join keeps untreated patients in the denominator.

WITH cohort AS (
    SELECT c.patient_id, c.first_onset_date AS dx_date
    FROM int_patient_conditions AS c
    CROSS JOIN params AS prm
    WHERE c.condition_group = 'Hypertension'
      AND c.first_onset_date >= prm.study_start
      AND c.first_onset_date <= prm.as_of_date - INTERVAL 365 DAY
),
class_starts AS (       -- first start date of each class per patient, after dx
    SELECT
        co.patient_id,
        co.dx_date,
        r.drug_class,
        MIN(CAST(m.start_ts AS DATE)) AS class_start_date
    FROM cohort AS co
    JOIN stg_medications AS m ON m.patient_id = co.patient_id
    JOIN ref_antihypertensives AS r ON r.rxnorm_code = m.rxnorm_code
    WHERE CAST(m.start_ts AS DATE) >= co.dx_date
    GROUP BY co.patient_id, co.dx_date, r.drug_class
),
ranked AS (
    SELECT *, DENSE_RANK() OVER (PARTITION BY patient_id ORDER BY class_start_date) AS line_rank
    FROM class_starts
),
per_patient AS (
    SELECT
        co.patient_id,
        MIN(r.class_start_date) FILTER (WHERE r.line_rank = 1)                         AS first_rx_date,
        STRING_AGG(DISTINCT r.drug_class, ' + ' ORDER BY r.drug_class)
            FILTER (WHERE r.line_rank = 1)                                             AS regimen,
        COUNT(*) FILTER (WHERE r.line_rank > 1) > 0                                    AS escalated,
        ANY_VALUE(co.dx_date)                                                          AS dx_date
    FROM cohort AS co
    LEFT JOIN ranked AS r USING (patient_id)
    GROUP BY co.patient_id
),
labelled AS (
    SELECT
        *,
        CASE WHEN first_rx_date IS NULL OR first_rx_date > dx_date + INTERVAL 365 DAY
             THEN 'No antihypertensive within 365 days'
             ELSE regimen
        END AS first_line_regimen,
        DATE_DIFF('day', dx_date, first_rx_date) AS days_to_first_rx
    FROM per_patient
)
SELECT
    first_line_regimen,
    COUNT(*)                                                       AS patients,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER (), 4)                     AS share_of_cohort,
    MEDIAN(days_to_first_rx)                                       AS median_days_to_first_rx,
    COUNT(*) FILTER (WHERE escalated)                              AS escalated_patients,
    ROUND(COUNT(*) FILTER (WHERE escalated) / COUNT(*), 4)         AS escalation_rate
FROM labelled
GROUP BY first_line_regimen
ORDER BY patients DESC, first_line_regimen;
