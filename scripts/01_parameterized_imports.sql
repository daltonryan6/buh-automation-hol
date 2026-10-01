/*=============================================================================
  Brown University Health - Automation & Governance Hands-On Lab
  Script 01: Parameterized Imports & Reusable Code
  
  GOAL: Replace hand-coded Clarity table imports with a single
        configuration-driven stored procedure.
  
  TIME: ~25 minutes
  PREREQUISITE: Run 00_setup.sql first
=============================================================================*/

USE DATABASE BUH_AUTOMATION_LAB;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================
-- PART A: The problem - hand-coded imports
-- ============================================================

-- This is what a hand-coded Clarity import looks like.
-- Imagine doing this for 50+ tables, each slightly different.

-- >>> STARTER: Run this to see the "old way" <<<
CREATE OR REPLACE TABLE CURATED.DIM_PATIENT AS
SELECT
    PAT_ID,
    PAT_MRN,
    PAT_FIRST_NAME,
    PAT_LAST_NAME,
    BIRTH_DATE,
    SSN,
    ADDRESS_LINE_1,
    CITY,
    STATE,
    ZIP_CODE,
    PHONE,
    EMAIL,
    GENDER,
    CURRENT_TIMESTAMP() AS LOADED_AT
FROM RAW.PATIENT_DIM;

SELECT * FROM CURATED.DIM_PATIENT LIMIT 5;

-- Now imagine writing that for ENCOUNTER_FACT, ORDERS,
-- and 47 more tables. Each one is slightly different,
-- each one can have a typo, each one is maintained separately.

-- ============================================================
-- PART B: Configuration-driven approach
-- ============================================================

-- Check what the config table tells us to import:
SELECT * FROM CURATED.IMPORT_CONFIG;

-- ============================================================
-- PART C: Build the parameterized import procedure
-- ============================================================

-- This single procedure can import ANY table listed in IMPORT_CONFIG.
-- It reads config, builds dynamic SQL, logs what it does.

CREATE OR REPLACE PROCEDURE CURATED.RUN_IMPORT(
    P_SOURCE_TABLE VARCHAR,
    P_BATCH_ID     VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_source_schema VARCHAR;
    v_target_schema VARCHAR;
    v_target_table  VARCHAR;
    v_key_columns   VARCHAR;
    v_sql           VARCHAR;
    v_run_id        VARCHAR;
    v_err           VARCHAR;
    v_detail        VARCHAR;
BEGIN
    -- Generate a run ID for traceability
    v_run_id := :P_BATCH_ID || '-' || REPLACE(CURRENT_TIMESTAMP()::VARCHAR, ' ', 'T');

    -- Look up config
    SELECT SOURCE_SCHEMA, TARGET_SCHEMA, TARGET_TABLE, KEY_COLUMNS
    INTO :v_source_schema, :v_target_schema, :v_target_table, :v_key_columns
    FROM CURATED.IMPORT_CONFIG
    WHERE SOURCE_TABLE = :P_SOURCE_TABLE
      AND ENABLED = TRUE;

    -- Log start (build JSON string to avoid OBJECT_CONSTRUCT limitation in VALUES)
    v_detail := '{"source":"' || :v_source_schema || '.' || :P_SOURCE_TABLE
             || '","target":"' || :v_target_schema || '.' || :v_target_table
             || '","batch_id":"' || :P_BATCH_ID || '"}';

    INSERT INTO LOGS.RUN_LOG (RUN_ID, STEP_NAME, LOG_LEVEL, MESSAGE, DETAIL)
    SELECT :v_run_id, 'RUN_IMPORT', 'INFO',
           'Starting import of ' || :P_SOURCE_TABLE,
           PARSE_JSON(:v_detail);

    -- Build and execute dynamic CTAS
    v_sql := 'CREATE OR REPLACE TABLE ' || :v_target_schema || '.' || :v_target_table
          || ' AS SELECT *, CURRENT_TIMESTAMP() AS LOADED_AT, '''
          || :P_BATCH_ID || ''' AS BATCH_ID FROM '
          || :v_source_schema || '.' || :P_SOURCE_TABLE;

    EXECUTE IMMEDIATE :v_sql;

    -- Log completion
    v_detail := '{"target":"' || :v_target_schema || '.' || :v_target_table || '"}';
    INSERT INTO LOGS.RUN_LOG (RUN_ID, STEP_NAME, LOG_LEVEL, MESSAGE, DETAIL)
    SELECT :v_run_id, 'RUN_IMPORT', 'INFO',
           'Completed import of ' || :P_SOURCE_TABLE,
           PARSE_JSON(:v_detail);

    -- Update config with last run info
    UPDATE CURATED.IMPORT_CONFIG
    SET LAST_RUN_TS = CURRENT_TIMESTAMP(),
        LAST_RUN_STATUS = 'SUCCESS'
    WHERE SOURCE_TABLE = :P_SOURCE_TABLE;

    RETURN 'SUCCESS: Loaded into ' || :v_target_schema || '.' || :v_target_table;

EXCEPTION
    WHEN OTHER THEN
        v_err := 'Import failed: ' || SQLCODE || ' - ' || SQLERRM;
        INSERT INTO LOGS.RUN_LOG (RUN_ID, STEP_NAME, LOG_LEVEL, MESSAGE)
        SELECT :v_run_id, 'RUN_IMPORT', 'ERROR', :v_err;

        UPDATE CURATED.IMPORT_CONFIG
        SET LAST_RUN_TS = CURRENT_TIMESTAMP(),
            LAST_RUN_STATUS = 'FAILED'
        WHERE SOURCE_TABLE = :P_SOURCE_TABLE;

        RETURN :v_err;
END;

-- ============================================================
-- PART D: Run the imports
-- ============================================================

-- Import all three tables with one batch ID
CALL CURATED.RUN_IMPORT('PATIENT_DIM', 'BATCH-2024-10-25-001');
CALL CURATED.RUN_IMPORT('ENCOUNTER_FACT', 'BATCH-2024-10-25-001');
CALL CURATED.RUN_IMPORT('ORDERS', 'BATCH-2024-10-25-001');

-- Check config updated
SELECT SOURCE_TABLE, TARGET_TABLE, LAST_RUN_TS, LAST_RUN_STATUS
FROM CURATED.IMPORT_CONFIG;

-- Check log entries
SELECT * FROM LOGS.RUN_LOG ORDER BY LOGGED_AT DESC LIMIT 10;

-- Check a loaded table
SELECT * FROM CURATED.FACT_ENCOUNTER LIMIT 5;

-- ============================================================
-- PART E: BONUS - A helper UDF for common transforms
-- ============================================================

-- Quick example: a UDF to standardize phone numbers
CREATE OR REPLACE FUNCTION CURATED.CLEAN_PHONE(raw_phone VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
    REGEXP_REPLACE(raw_phone, '[^0-9]', '')
$$;

-- Test it
SELECT
    PHONE AS RAW_PHONE,
    CURATED.CLEAN_PHONE(PHONE) AS CLEANED_PHONE
FROM CURATED.DIM_PATIENT;

-- ============================================================
-- PART F: BONUS - Run all enabled imports in a loop
-- ============================================================

CREATE OR REPLACE PROCEDURE CURATED.RUN_ALL_IMPORTS(P_BATCH_ID VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    c CURSOR FOR
        SELECT SOURCE_TABLE
        FROM CURATED.IMPORT_CONFIG
        WHERE ENABLED = TRUE
        ORDER BY CONFIG_ID;
    v_table   VARCHAR;
    v_result  VARCHAR;
    v_summary VARCHAR DEFAULT '';
BEGIN
    FOR rec IN c DO
        v_table := rec.SOURCE_TABLE;
        CALL CURATED.RUN_IMPORT(:v_table, :P_BATCH_ID);
        v_summary := :v_summary || :v_table || ': done; ';
    END FOR;
    RETURN :v_summary;
END;

-- Run all imports in one call
CALL CURATED.RUN_ALL_IMPORTS('BATCH-2024-10-25-002');

-- ============================================================
-- CHECKPOINT: You should see
--   - 3 config rows with LAST_RUN_STATUS = SUCCESS
--   - Log entries for each import
--   - DIM_PATIENT, FACT_ENCOUNTER, FACT_ORDERS in CURATED
-- ============================================================
SELECT SOURCE_TABLE, LAST_RUN_TS, LAST_RUN_STATUS FROM CURATED.IMPORT_CONFIG;
