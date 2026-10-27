-- =============================================================================
-- 00_load.sql  -  land the raw Synthea extract in DuckDB
-- =============================================================================
-- Raw tables are copied 1:1 from the Parquet files in data/raw/ (every column
-- is text, exactly as Synthea wrote it). Nothing is cleaned here; typing and
-- renaming happen in 01_staging.sql so that the raw layer stays auditable.
--
-- Paths are relative to the repository root, so this also works from the
-- DuckDB CLI:   duckdb ehr.duckdb < sql/00_load.sql
-- (the Python runner rewrites 'data/' to an absolute path).
-- =============================================================================

CREATE OR REPLACE TABLE raw_patients      AS SELECT * FROM read_parquet('data/raw/patients.parquet');
CREATE OR REPLACE TABLE raw_encounters    AS SELECT * FROM read_parquet('data/raw/encounters.parquet');
CREATE OR REPLACE TABLE raw_conditions    AS SELECT * FROM read_parquet('data/raw/conditions.parquet');
CREATE OR REPLACE TABLE raw_medications   AS SELECT * FROM read_parquet('data/raw/medications.parquet');
CREATE OR REPLACE TABLE raw_observations  AS SELECT * FROM read_parquet('data/raw/observations.parquet');
CREATE OR REPLACE TABLE raw_organizations AS SELECT * FROM read_parquet('data/raw/organizations.parquet');
CREATE OR REPLACE TABLE raw_payers        AS SELECT * FROM read_parquet('data/raw/payers.parquet');

-- Hand-curated reference tables (see the notes column in each CSV)
CREATE OR REPLACE TABLE ref_condition_groups AS
SELECT * FROM read_csv('data/reference/condition_groups.csv', header = true, all_varchar = true);

CREATE OR REPLACE TABLE ref_antihypertensives AS
SELECT * FROM read_csv('data/reference/antihypertensives.csv', header = true, all_varchar = true);

CREATE OR REPLACE TABLE ref_planned_admission_reasons AS
SELECT * FROM read_csv('data/reference/planned_admission_reasons.csv', header = true, all_varchar = true);
