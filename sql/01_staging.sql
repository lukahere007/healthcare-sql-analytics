-- =============================================================================
-- 01_staging.sql  -  typed, renamed, one-row-per-entity views over raw_*
-- =============================================================================
-- Conventions
--   * snake_case column names, *_id for keys, *_ts for timestamps, *_date for dates
--   * Synthea writes UTC timestamps like 2015-05-27T11:50:11Z; we parse them with
--     TRY_STRPTIME so a malformed value becomes NULL (and is caught by the
--     data-quality checks) instead of aborting the whole load.
--   * Money is DECIMAL(12,2); free-text values are kept as text.
-- =============================================================================

-- Analysis parameters live in one table so every query uses the same dates.
--   as_of_date   : the "today" of the analysis = the date Synthea stopped simulating
--   study_start  : Synthea keeps ~10 years of detailed history (exporter.years_of_history
--                  = 10), so encounter-level metrics are restricted to this window
CREATE OR REPLACE TABLE params AS
SELECT DATE '2025-06-30' AS as_of_date,
       DATE '2015-07-01' AS study_start;

-- Exact age in whole years (DATE_DIFF('year', ...) would count calendar-year
-- boundaries, which overstates age before the birthday).
CREATE OR REPLACE MACRO age_years(birth, at_date) AS
    CAST(EXTRACT(YEAR FROM AGE(CAST(at_date AS DATE), CAST(birth AS DATE))) AS INTEGER);

CREATE OR REPLACE MACRO age_band(age) AS
    CASE
        WHEN age < 18 THEN '0-17'
        WHEN age < 40 THEN '18-39'
        WHEN age < 65 THEN '40-64'
        WHEN age < 75 THEN '65-74'
        WHEN age < 85 THEN '75-84'
        ELSE '85+'
    END;

CREATE OR REPLACE MACRO parse_ts(x) AS TRY_STRPTIME(x, '%Y-%m-%dT%H:%M:%SZ');

-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW stg_patients AS
SELECT
    Id                                   AS patient_id,
    TRY_CAST(BIRTHDATE AS DATE)          AS birth_date,
    TRY_CAST(DEATHDATE AS DATE)          AS death_date,
    GENDER                               AS gender,
    RACE                                 AS race,
    ETHNICITY                            AS ethnicity,
    MARITAL                              AS marital_status,
    COUNTY                               AS county,
    TRY_CAST(INCOME AS INTEGER)          AS income
FROM raw_patients;

CREATE OR REPLACE VIEW stg_encounters AS
SELECT
    Id                                          AS encounter_id,
    PATIENT                                     AS patient_id,
    ORGANIZATION                                AS organization_id,
    PAYER                                       AS payer_id,
    ENCOUNTERCLASS                              AS encounter_class,
    parse_ts(START)                             AS start_ts,
    parse_ts(STOP)                              AS stop_ts,
    CODE                                        AS encounter_code,
    DESCRIPTION                                 AS encounter_description,
    NULLIF(REASONCODE, '')                      AS reason_code,
    NULLIF(REASONDESCRIPTION, '')               AS reason_description,
    TRY_CAST(BASE_ENCOUNTER_COST AS DECIMAL(12, 2)) AS base_cost,
    TRY_CAST(TOTAL_CLAIM_COST    AS DECIMAL(12, 2)) AS total_claim_cost,
    TRY_CAST(PAYER_COVERAGE      AS DECIMAL(12, 2)) AS payer_coverage
FROM raw_encounters;

CREATE OR REPLACE VIEW stg_conditions AS
SELECT
    PATIENT                         AS patient_id,
    ENCOUNTER                       AS encounter_id,
    CODE                            AS condition_code,
    DESCRIPTION                     AS condition_description,
    TRY_CAST(START AS DATE)         AS onset_date,
    TRY_CAST(STOP  AS DATE)         AS resolved_date      -- NULL = still active
FROM raw_conditions;

CREATE OR REPLACE VIEW stg_medications AS
SELECT
    PATIENT                                   AS patient_id,
    ENCOUNTER                                 AS encounter_id,
    PAYER                                     AS payer_id,
    CODE                                      AS rxnorm_code,
    DESCRIPTION                               AS medication_description,
    parse_ts(START)                           AS start_ts,
    parse_ts(STOP)                            AS stop_ts,  -- NULL = still being taken
    NULLIF(REASONCODE, '')                    AS reason_code,
    NULLIF(REASONDESCRIPTION, '')             AS reason_description,
    TRY_CAST(DISPENSES AS INTEGER)            AS dispenses,
    TRY_CAST(TOTALCOST AS DECIMAL(12, 2))     AS total_cost
FROM raw_medications;

CREATE OR REPLACE VIEW stg_observations AS
SELECT
    PATIENT                         AS patient_id,
    NULLIF(ENCOUNTER, '')           AS encounter_id,
    parse_ts(DATE)                  AS observation_ts,
    CATEGORY                        AS category,
    CODE                            AS loinc_code,
    DESCRIPTION                     AS observation_description,
    TRY_CAST(VALUE AS DOUBLE)       AS value_numeric,     -- NULL for coded/text answers
    VALUE                           AS value_text,
    UNITS                           AS units
FROM raw_observations;

CREATE OR REPLACE VIEW stg_payers AS
SELECT Id AS payer_id, NAME AS payer_name, OWNERSHIP AS ownership
FROM raw_payers;
