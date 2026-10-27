-- title: Polypharmacy among patients aged 65+ (peak concurrent medications, last 12 months)
-- grain: age_band
-- rate_columns: polypharmacy_rate, hyper_polypharmacy_rate, polypharmacy_on_as_of_rate
--
-- Question
--   Among living patients aged 65+, how many were exposed to polypharmacy
--   (>= 5 different drugs at the same time) during the 12 months before the
--   as-of date? How many to hyper-polypharmacy (>= 10)?
--
-- Definitions
--   Drug exposure   : int_medication_episodes - prescriptions of the same RxNorm
--                     code merged into continuous episodes (gaps-and-islands with
--                     a 30-day grace period), so a monthly refill is one drug,
--                     not twelve.
--   Concurrent count: number of distinct episodes active at the same instant.
--   Look-back       : (as_of_date - 365 days, as_of_date].
--
-- Technique
--   "Sweep line": each episode becomes a +1 event at its start and a -1 event
--   at its end (clipped to the look-back window). A running SUM over events in
--   time order is the number of drugs on board at each moment; its MAX per
--   patient is the peak. At equal timestamps -1 sorts first, so a drug that
--   stops exactly when another starts is not counted as overlapping.

WITH cohort AS (
    SELECT patient_id, age_band_at_as_of AS age_band
    FROM int_patients
    WHERE alive_at_as_of AND age_at_as_of >= 65
),
window_bounds AS (
    SELECT CAST(as_of_date - INTERVAL 365 DAY AS TIMESTAMP) AS win_start,
           CAST(as_of_date AS TIMESTAMP)                    AS win_end
    FROM params
),
episodes_in_window AS (
    SELECT
        e.patient_id,
        e.rxnorm_code,
        GREATEST(e.episode_start_ts, w.win_start) AS clip_start,
        LEAST(e.episode_end_ts, w.win_end)        AS clip_end
    FROM int_medication_episodes AS e
    JOIN cohort USING (patient_id)
    CROSS JOIN window_bounds AS w
    WHERE e.episode_start_ts < w.win_end
      AND e.episode_end_ts   > w.win_start
),
events AS (
    SELECT patient_id, clip_start AS event_ts, +1 AS delta FROM episodes_in_window
    UNION ALL
    SELECT patient_id, clip_end   AS event_ts, -1 AS delta FROM episodes_in_window
),
running AS (
    SELECT
        patient_id,
        event_ts,
        SUM(delta) OVER (PARTITION BY patient_id ORDER BY event_ts, delta
                         ROWS UNBOUNDED PRECEDING) AS meds_on_board
    FROM events
),
per_patient AS (
    SELECT
        c.patient_id,
        c.age_band,
        COALESCE(MAX(r.meds_on_board), 0) AS peak_concurrent_meds
    FROM cohort AS c
    LEFT JOIN running AS r USING (patient_id)        -- keep patients with no meds
    GROUP BY c.patient_id, c.age_band
),
on_as_of AS (   -- point-prevalence check: distinct drugs active on the as-of date itself
    SELECT e.patient_id, COUNT(DISTINCT e.rxnorm_code) AS meds_on_as_of
    FROM int_medication_episodes AS e
    CROSS JOIN window_bounds AS w
    WHERE e.episode_start_ts <= w.win_end AND e.episode_end_ts >= w.win_end
    GROUP BY e.patient_id
)
SELECT
    CASE WHEN GROUPING(p.age_band) = 1 THEN '65+ (all)' ELSE p.age_band END AS age_band,
    COUNT(*)                                                           AS patients,
    MEDIAN(p.peak_concurrent_meds)                                     AS median_peak_meds,
    COUNT(*) FILTER (WHERE p.peak_concurrent_meds >= 5)                AS polypharmacy_patients,
    ROUND(COUNT(*) FILTER (WHERE p.peak_concurrent_meds >= 5)  / COUNT(*), 4) AS polypharmacy_rate,
    ROUND(COUNT(*) FILTER (WHERE p.peak_concurrent_meds >= 10) / COUNT(*), 4) AS hyper_polypharmacy_rate,
    ROUND(COUNT(*) FILTER (WHERE COALESCE(o.meds_on_as_of, 0) >= 5) / COUNT(*), 4) AS polypharmacy_on_as_of_rate
FROM per_patient AS p
LEFT JOIN on_as_of AS o USING (patient_id)
GROUP BY GROUPING SETS ((p.age_band), ())
ORDER BY GROUPING(p.age_band), age_band;
