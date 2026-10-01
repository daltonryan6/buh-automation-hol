/*=============================================================================
  Brown University Health - Automation & Governance Hands-On Lab
  Script 02: Resilient Vendor File Ingestion
  
  GOAL: Process vendor lab result files through validation,
        route good rows to ACCEPTED and bad rows to QUARANTINE,
        handle schema drift, and support safe re-runs.
  
  TIME: ~20 minutes
  PREREQUISITE: Run 00_setup.sql and 01_parameterized_imports.sql
=============================================================================*/

USE DATABASE BUH_AUTOMATION_LAB;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================
-- PART A: Explore the vendor payloads
-- ============================================================

-- Good payload - matches expected schema
SELECT * FROM VENDOR_LANDING.VENDOR_LAB_BATCH_GOOD;

-- Drifted payload - has unexpected extra columns
SELECT * FROM VENDOR_LANDING.VENDOR_LAB_BATCH_DRIFTED;

-- Invalid payload - missing required fields, bad formats
SELECT * FROM VENDOR_LANDING.VENDOR_LAB_BATCH_INVALID;

-- What does the expected schema look like?
SELECT * FROM VENDOR_LANDING.VENDOR_LAB_EXPECTED_SCHEMA;

-- ============================================================
-- PART B: Build the validation function
-- ============================================================

-- This UDTF validates each row against business rules and returns
-- a pass/fail verdict with reasons.
CREATE OR REPLACE FUNCTION VENDOR_LANDING.VALIDATE_VENDOR_LAB_ROW(
    p_vendor_id    VARCHAR,
    p_pat_mrn      VARCHAR,
    p_test_code    VARCHAR,
    p_result_date  DATE,
    p_abnormal_yn  VARCHAR
)
RETURNS TABLE (IS_VALID BOOLEAN, REJECTION_REASONS ARRAY)
LANGUAGE SQL
AS
$$
    SELECT
        ARRAY_SIZE(reasons) = 0 AS IS_VALID,
        reasons AS REJECTION_REASONS
    FROM (
        SELECT ARRAY_CAT(
            ARRAY_CAT(
                ARRAY_CAT(
                    ARRAY_CAT(
                        CASE WHEN p_vendor_id IS NULL
                             THEN ARRAY_CONSTRUCT('VENDOR_ID is NULL')
                             WHEN NOT REGEXP_LIKE(p_vendor_id, '^VL-[0-9]{6}$')
                             THEN ARRAY_CONSTRUCT('VENDOR_ID format invalid: ' || NVL(p_vendor_id, 'NULL'))
                             ELSE ARRAY_CONSTRUCT() END,
                        CASE WHEN p_pat_mrn IS NULL
                             THEN ARRAY_CONSTRUCT('PAT_MRN is NULL')
                             WHEN NOT REGEXP_LIKE(p_pat_mrn, '^MRN-[0-9]{6}$')
                             THEN ARRAY_CONSTRUCT('PAT_MRN format invalid: ' || NVL(p_pat_mrn, 'NULL'))
                             ELSE ARRAY_CONSTRUCT() END
                    ),
                    CASE WHEN p_test_code IS NULL
                         THEN ARRAY_CONSTRUCT('TEST_CODE is NULL')
                         ELSE ARRAY_CONSTRUCT() END
                ),
                CASE WHEN p_result_date IS NULL
                     THEN ARRAY_CONSTRUCT('RESULT_DATE is NULL')
                     ELSE ARRAY_CONSTRUCT() END
            ),
            CASE WHEN p_abnormal_yn IS NOT NULL AND p_abnormal_yn NOT IN ('Y','N')
                 THEN ARRAY_CONSTRUCT('ABNORMAL_YN invalid value: ' || p_abnormal_yn)
                 ELSE ARRAY_CONSTRUCT() END
        ) AS reasons
    )
$$;

-- Test the validator on one good row
SELECT v.*
FROM TABLE(VENDOR_LANDING.VALIDATE_VENDOR_LAB_ROW(
    'VL-000001', 'MRN-900001', 'GLU', '2024-10-20'::DATE, 'N'
)) v;

-- Test the validator on one bad row
SELECT v.*
FROM TABLE(VENDOR_LANDING.VALIDATE_VENDOR_LAB_ROW(
    'BADID', NULL, NULL, NULL, 'X'
)) v;

-- ============================================================
-- PART C: Build the ingestion procedure
-- ============================================================

CREATE OR REPLACE PROCEDURE VENDOR_LANDING.PROCESS_VENDOR_BATCH(
    P_BATCH_TABLE VARCHAR,
    P_BATCH_ID    VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
DECLARE
    v_run_id       VARCHAR;
    v_accepted     NUMBER DEFAULT 0;
    v_quarantined  NUMBER DEFAULT 0;
    v_sql          VARCHAR;
    v_err          VARCHAR;
    v_detail       VARCHAR;
BEGIN
    v_run_id := :P_BATCH_ID || '-' || REPLACE(CURRENT_TIMESTAMP()::VARCHAR, ' ', 'T');

    -- Log start
    INSERT INTO LOGS.RUN_LOG (RUN_ID, STEP_NAME, LOG_LEVEL, MESSAGE)
    SELECT :v_run_id, 'PROCESS_VENDOR_BATCH', 'INFO',
           'Processing vendor batch: ' || :P_BATCH_TABLE || ' as ' || :P_BATCH_ID;

    -- Step 1: Schema drift detection
    LET v_incoming_cols NUMBER := (
        SELECT COUNT(*)
        FROM BUH_AUTOMATION_LAB.INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = 'VENDOR_LANDING'
          AND TABLE_NAME = UPPER(:P_BATCH_TABLE)
    );

    LET v_expected_cols NUMBER := (
        SELECT COUNT(*) FROM VENDOR_LANDING.VENDOR_LAB_EXPECTED_SCHEMA
    );

    IF (v_incoming_cols > v_expected_cols) THEN
        v_detail := '{"incoming_cols":' || :v_incoming_cols || ',"expected_cols":' || :v_expected_cols || '}';
        INSERT INTO LOGS.RUN_LOG (RUN_ID, STEP_NAME, LOG_LEVEL, MESSAGE, DETAIL)
        SELECT :v_run_id, 'PROCESS_VENDOR_BATCH', 'WARN',
               'Schema drift detected: incoming has ' || :v_incoming_cols
               || ' columns, expected ' || :v_expected_cols,
               PARSE_JSON(:v_detail);
    END IF;

    -- Step 2: Validate and route rows
    -- Insert accepted rows
    v_sql := '
        INSERT INTO VENDOR_LANDING.VENDOR_LAB_ACCEPTED
            (VENDOR_ID, PAT_MRN, TEST_CODE, TEST_NAME, RESULT_VALUE,
             RESULT_UNIT, RESULT_DATE, ABNORMAL_YN, BATCH_ID)
        SELECT
            src.VENDOR_ID, src.PAT_MRN, src.TEST_CODE, src.TEST_NAME,
            src.RESULT_VALUE, src.RESULT_UNIT, src.RESULT_DATE,
            src.ABNORMAL_YN, ''' || :P_BATCH_ID || '''
        FROM VENDOR_LANDING.' || :P_BATCH_TABLE || ' src,
             TABLE(VENDOR_LANDING.VALIDATE_VENDOR_LAB_ROW(
                 src.VENDOR_ID, src.PAT_MRN, src.TEST_CODE,
                 src.RESULT_DATE, src.ABNORMAL_YN)) v
        WHERE v.IS_VALID = TRUE';

    EXECUTE IMMEDIATE :v_sql;
    v_accepted := (SELECT COUNT(*) FROM VENDOR_LANDING.VENDOR_LAB_ACCEPTED WHERE BATCH_ID = :P_BATCH_ID);

    -- Insert quarantined rows
    v_sql := '
        INSERT INTO VENDOR_LANDING.VENDOR_LAB_QUARANTINE
            (VENDOR_ID, PAT_MRN, TEST_CODE, TEST_NAME, RESULT_VALUE,
             RESULT_UNIT, RESULT_DATE, ABNORMAL_YN, BATCH_ID, REJECTION_REASONS)
        SELECT
            src.VENDOR_ID, src.PAT_MRN, src.TEST_CODE, src.TEST_NAME,
            src.RESULT_VALUE, src.RESULT_UNIT, src.RESULT_DATE,
            src.ABNORMAL_YN, ''' || :P_BATCH_ID || ''',
            v.REJECTION_REASONS::VARIANT
        FROM VENDOR_LANDING.' || :P_BATCH_TABLE || ' src,
             TABLE(VENDOR_LANDING.VALIDATE_VENDOR_LAB_ROW(
                 src.VENDOR_ID, src.PAT_MRN, src.TEST_CODE,
                 src.RESULT_DATE, src.ABNORMAL_YN)) v
        WHERE v.IS_VALID = FALSE';

    EXECUTE IMMEDIATE :v_sql;
    v_quarantined := (SELECT COUNT(*) FROM VENDOR_LANDING.VENDOR_LAB_QUARANTINE WHERE BATCH_ID = :P_BATCH_ID);

    -- Log completion
    v_detail := '{"accepted":' || :v_accepted || ',"quarantined":' || :v_quarantined
             || ',"batch_id":"' || :P_BATCH_ID || '"}';
    INSERT INTO LOGS.RUN_LOG (RUN_ID, STEP_NAME, LOG_LEVEL, MESSAGE, DETAIL)
    SELECT :v_run_id, 'PROCESS_VENDOR_BATCH', 'INFO',
           'Batch complete: ' || :v_accepted || ' accepted, ' || :v_quarantined || ' quarantined',
           PARSE_JSON(:v_detail);

    IF (:v_quarantined > 0) THEN
        INSERT INTO LOGS.RUN_LOG (RUN_ID, STEP_NAME, LOG_LEVEL, MESSAGE)
        SELECT :v_run_id, 'PROCESS_VENDOR_BATCH', 'WARN',
               :v_quarantined || ' rows quarantined - review VENDOR_LAB_QUARANTINE';
    END IF;

    RETURN 'Accepted: ' || :v_accepted || ', Quarantined: ' || :v_quarantined;

EXCEPTION
    WHEN OTHER THEN
        v_err := 'Batch processing failed: ' || SQLCODE || ' - ' || SQLERRM;
        INSERT INTO LOGS.RUN_LOG (RUN_ID, STEP_NAME, LOG_LEVEL, MESSAGE)
        SELECT :v_run_id, 'PROCESS_VENDOR_BATCH', 'ERROR', :v_err;
        RETURN 'FAILED: ' || SQLERRM;
END;

-- ============================================================
-- PART D: Process each batch
-- ============================================================

-- Good batch - all rows should pass
CALL VENDOR_LANDING.PROCESS_VENDOR_BATCH('VENDOR_LAB_BATCH_GOOD', 'GOOD-001');

-- Drifted batch - rows pass but drift is logged as WARN
CALL VENDOR_LANDING.PROCESS_VENDOR_BATCH('VENDOR_LAB_BATCH_DRIFTED', 'DRIFT-001');

-- Invalid batch - rows quarantined with rejection reasons
CALL VENDOR_LANDING.PROCESS_VENDOR_BATCH('VENDOR_LAB_BATCH_INVALID', 'INVALID-001');

-- ============================================================
-- PART E: Inspect results
-- ============================================================

-- Accepted rows
SELECT * FROM VENDOR_LANDING.VENDOR_LAB_ACCEPTED ORDER BY BATCH_ID, VENDOR_ID;

-- Quarantined rows with reasons
SELECT
    VENDOR_ID,
    PAT_MRN,
    TEST_CODE,
    BATCH_ID,
    REJECTION_REASONS::VARCHAR AS REASONS
FROM VENDOR_LANDING.VENDOR_LAB_QUARANTINE
ORDER BY BATCH_ID;

-- Check the log for warnings and errors
SELECT RUN_ID, LOG_LEVEL, MESSAGE
FROM LOGS.RUN_LOG
WHERE LOG_LEVEL IN ('WARN', 'ERROR')
ORDER BY LOGGED_AT DESC;

-- ============================================================
-- PART F: Safe re-run (idempotency discussion)
-- ============================================================

-- What happens if we re-run the good batch?
-- Currently it would duplicate rows. In production you would:
-- 1. DELETE FROM ACCEPTED WHERE BATCH_ID = 'GOOD-001' first, or
-- 2. Use MERGE instead of INSERT, or
-- 3. Check if batch already processed

-- Quick reset for re-run:
-- DELETE FROM VENDOR_LANDING.VENDOR_LAB_ACCEPTED WHERE BATCH_ID = 'GOOD-001';
-- DELETE FROM VENDOR_LANDING.VENDOR_LAB_QUARANTINE WHERE BATCH_ID = 'GOOD-001';
-- CALL VENDOR_LANDING.PROCESS_VENDOR_BATCH('VENDOR_LAB_BATCH_GOOD', 'GOOD-001');

-- ============================================================
-- CHECKPOINT: You should see
--   - 7 accepted rows (5 good + 2 drifted)
--   - 4 quarantined rows (all from invalid batch)
--   - WARN log entries for schema drift and quarantine count
-- ============================================================
SELECT 'ACCEPTED' AS STATUS, COUNT(*) AS CNT FROM VENDOR_LANDING.VENDOR_LAB_ACCEPTED
UNION ALL
SELECT 'QUARANTINED', COUNT(*) FROM VENDOR_LANDING.VENDOR_LAB_QUARANTINE;
