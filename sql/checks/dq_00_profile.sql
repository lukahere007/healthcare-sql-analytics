-- title: Data profile - row counts and null rates per staged column
-- severity: info
-- grain: table_name, column_name
-- rate_columns: null_rate
--
-- Informational (never fails). DuckDB's COLUMNS(*) applies the same
-- expression to every column; UNPIVOT turns the one wide row into one row per
-- column, so the profile does not need to be edited when a column is added.

WITH null_rates AS (
    SELECT 'stg_patients' AS table_name, * FROM (
        UNPIVOT (SELECT AVG(CASE WHEN COLUMNS(*) IS NULL THEN 1.0 ELSE 0.0 END) FROM stg_patients)
        ON COLUMNS(*) INTO NAME column_name VALUE null_rate)
    UNION ALL
    SELECT 'stg_encounters', * FROM (
        UNPIVOT (SELECT AVG(CASE WHEN COLUMNS(*) IS NULL THEN 1.0 ELSE 0.0 END) FROM stg_encounters)
        ON COLUMNS(*) INTO NAME column_name VALUE null_rate)
    UNION ALL
    SELECT 'stg_conditions', * FROM (
        UNPIVOT (SELECT AVG(CASE WHEN COLUMNS(*) IS NULL THEN 1.0 ELSE 0.0 END) FROM stg_conditions)
        ON COLUMNS(*) INTO NAME column_name VALUE null_rate)
    UNION ALL
    SELECT 'stg_medications', * FROM (
        UNPIVOT (SELECT AVG(CASE WHEN COLUMNS(*) IS NULL THEN 1.0 ELSE 0.0 END) FROM stg_medications)
        ON COLUMNS(*) INTO NAME column_name VALUE null_rate)
    UNION ALL
    SELECT 'stg_observations', * FROM (
        UNPIVOT (SELECT AVG(CASE WHEN COLUMNS(*) IS NULL THEN 1.0 ELSE 0.0 END) FROM stg_observations)
        ON COLUMNS(*) INTO NAME column_name VALUE null_rate)
),
row_counts AS (
    SELECT 'stg_patients' AS table_name, COUNT(*) AS row_count FROM stg_patients
    UNION ALL SELECT 'stg_encounters',   COUNT(*) FROM stg_encounters
    UNION ALL SELECT 'stg_conditions',   COUNT(*) FROM stg_conditions
    UNION ALL SELECT 'stg_medications',  COUNT(*) FROM stg_medications
    UNION ALL SELECT 'stg_observations', COUNT(*) FROM stg_observations
)
SELECT n.table_name, r.row_count, n.column_name, ROUND(n.null_rate, 4) AS null_rate
FROM null_rates AS n
JOIN row_counts AS r USING (table_name)
ORDER BY n.table_name, n.column_name;
