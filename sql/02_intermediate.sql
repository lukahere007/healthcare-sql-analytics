-- =============================================================================
-- 02_intermediate.sql  -  reusable analytical building blocks
-- =============================================================================
-- These views encode the definitions that several questions share, so a
-- definition (what is an inpatient stay? which patients are "alive"?) lives in
-- exactly one place.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- int_patients: one row per patient with age / vital status at the as-of date
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW int_patients AS
SELECT
    p.*,
    (p.death_date IS NULL OR p.death_date > prm.as_of_date)          AS alive_at_as_of,
    age_years(p.birth_date, prm.as_of_date)                          AS age_at_as_of,
    age_band(age_years(p.birth_date, prm.as_of_date))                AS age_band_at_as_of
FROM stg_patients AS p
CROSS JOIN params AS prm;


-- -----------------------------------------------------------------------------
-- int_patient_conditions: one row per patient x condition group
--   first_onset_date      earliest onset of any code in the group
--   active_at_as_of       at least one code in the group was active on as_of_date
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW int_patient_conditions AS
SELECT
    c.patient_id,
    g.condition_group,
    MIN(c.onset_date)                                                AS first_onset_date,
    BOOL_OR(c.onset_date <= prm.as_of_date
            AND (c.resolved_date IS NULL OR c.resolved_date > prm.as_of_date))
                                                                     AS active_at_as_of
FROM stg_conditions AS c
JOIN ref_condition_groups AS g ON g.snomed_code = c.condition_code
CROSS JOIN params AS prm
GROUP BY c.patient_id, g.condition_group;


-- -----------------------------------------------------------------------------
-- int_inpatient_stays: inpatient encounters collapsed into hospital stays
-- -----------------------------------------------------------------------------
-- Synthea sometimes records one hospitalisation as several overlapping
-- inpatient encounters (e.g. ward -> ICU transfer). Counting each as a separate
-- admission would invent "readmissions" on the same day, so we merge them.
--
-- Gaps-and-islands: walk each patient's inpatient encounters in start order and
-- keep the running maximum stop time of everything seen so far. An encounter
-- that starts at or before that running max belongs to the current stay;
-- otherwise it opens a new stay. A running SUM of the "new stay" flag numbers
-- the islands.
CREATE OR REPLACE VIEW int_inpatient_stays AS
WITH inpatient AS (
    SELECT
        e.*,
        MAX(e.stop_ts) OVER (
            PARTITION BY e.patient_id
            ORDER BY e.start_ts, e.encounter_id
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_max_stop_ts
    FROM stg_encounters AS e
    WHERE e.encounter_class = 'inpatient'
),
islands AS (
    SELECT
        *,
        CAST(SUM(CASE WHEN prev_max_stop_ts IS NULL OR start_ts > prev_max_stop_ts THEN 1 ELSE 0 END)
            OVER (PARTITION BY patient_id ORDER BY start_ts, encounter_id
                  ROWS UNBOUNDED PRECEDING) AS INTEGER) AS stay_seq
    FROM inpatient
)
SELECT
    patient_id || ':' || stay_seq                                    AS stay_id,
    patient_id,
    stay_seq,
    MIN(start_ts)                                                    AS admit_ts,
    MAX(stop_ts)                                                     AS discharge_ts,
    CAST(MIN(start_ts) AS DATE)                                      AS admit_date,
    CAST(MAX(stop_ts)  AS DATE)                                      AS discharge_date,
    -- midnight-count LOS (0 = admitted and discharged on the same calendar day)
    DATE_DIFF('day', CAST(MIN(start_ts) AS DATE), CAST(MAX(stop_ts) AS DATE)) AS los_days,
    COUNT(*)                                                         AS n_encounters,
    -- principal reason = reason recorded on the first encounter of the stay
    COALESCE(ARG_MIN(reason_description, start_ts), '(no reason recorded)') AS principal_reason,
    SUM(total_claim_cost)                                            AS stay_cost
FROM islands
GROUP BY patient_id, stay_seq;


-- -----------------------------------------------------------------------------
-- int_medication_episodes: continuous exposure to one drug
-- -----------------------------------------------------------------------------
-- Synthea re-issues chronic prescriptions as back-to-back records (one per
-- refill period), sometimes overlapping, sometimes with a short gap. We merge
-- records of the same patient + RxNorm code into one episode when the next
-- record starts no more than 30 days (the "grace period") after the latest
-- stop seen so far - the same gaps-and-islands pattern as above.
-- Open prescriptions (stop_ts NULL) are treated as running to the as-of date.
CREATE OR REPLACE VIEW int_medication_episodes AS
WITH rx AS (
    SELECT
        m.patient_id,
        m.rxnorm_code,
        m.medication_description,
        m.start_ts,
        LEAST(COALESCE(m.stop_ts, CAST(prm.as_of_date AS TIMESTAMP)),
              CAST(prm.as_of_date AS TIMESTAMP))                     AS stop_ts
    FROM stg_medications AS m
    CROSS JOIN params AS prm
    WHERE m.start_ts <= CAST(prm.as_of_date AS TIMESTAMP)
      -- a few source records stop before they start (see sql/checks/dq_05);
      -- they would create negative exposure, so they are dropped here
      AND (m.stop_ts IS NULL OR m.stop_ts >= m.start_ts)
),
flagged AS (
    SELECT
        *,
        MAX(stop_ts) OVER (
            PARTITION BY patient_id, rxnorm_code
            ORDER BY start_ts
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
        ) AS prev_max_stop_ts
    FROM rx
),
islands AS (
    SELECT
        *,
        CAST(SUM(CASE WHEN prev_max_stop_ts IS NULL
                        OR start_ts > prev_max_stop_ts + INTERVAL 30 DAY THEN 1 ELSE 0 END)
            OVER (PARTITION BY patient_id, rxnorm_code ORDER BY start_ts
                  ROWS UNBOUNDED PRECEDING) AS INTEGER) AS episode_seq
    FROM flagged
)
SELECT
    patient_id,
    rxnorm_code,
    ANY_VALUE(medication_description)  AS medication_description,
    episode_seq,
    MIN(start_ts)                      AS episode_start_ts,
    MAX(stop_ts)                       AS episode_end_ts,
    COUNT(*)                           AS n_prescriptions
FROM islands
GROUP BY patient_id, rxnorm_code, episode_seq;
