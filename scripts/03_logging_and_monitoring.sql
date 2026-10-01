/*=============================================================================
  Brown University Health - Automation & Governance Hands-On Lab
  Script 03: Centralized Logging & Error Reporting
  
  GOAL: Use the RUN_LOG table as a single pane of glass for pipeline
        observability. Build operational queries, a summary view,
        and discuss event table and alerting extensions.
  
  TIME: ~20 minutes
  PREREQUISITE: Run 00-02 first (generates log entries)
=============================================================================*/

USE DATABASE BUH_AUTOMATION_LAB;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================
-- PART A: Explore existing logs
-- ============================================================

-- Everything that happened during the lab so far
SELECT * FROM LOGS.RUN_LOG ORDER BY LOGGED_AT DESC;

-- Filter to warnings and errors only
SELECT
    RUN_ID,
    STEP_NAME,
    LOG_LEVEL,
    MESSAGE,
    LOGGED_AT
FROM LOGS.RUN_LOG
WHERE LOG_LEVEL IN ('WARN', 'ERROR')
ORDER BY LOGGED_AT DESC;

-- ============================================================
-- PART B: Build an operational dashboard view
-- ============================================================

CREATE OR REPLACE VIEW LOGS.RUN_SUMMARY AS
SELECT
    DATE_TRUNC('hour', LOGGED_AT)        AS LOG_HOUR,
    STEP_NAME,
    LOG_LEVEL,
    COUNT(*)                              AS EVENT_COUNT,
    MIN(LOGGED_AT)                        AS FIRST_EVENT,
    MAX(LOGGED_AT)                        AS LAST_EVENT
FROM LOGS.RUN_LOG
GROUP BY 1, 2, 3
ORDER BY LOG_HOUR DESC, LOG_LEVEL;

SELECT * FROM LOGS.RUN_SUMMARY;

-- Per-batch summary
CREATE OR REPLACE VIEW LOGS.BATCH_HEALTH AS
SELECT
    SPLIT_PART(RUN_ID, '-', 1) || '-' || SPLIT_PART(RUN_ID, '-', 2) AS BATCH_PREFIX,
    COUNT_IF(LOG_LEVEL = 'INFO')  AS INFO_COUNT,
    COUNT_IF(LOG_LEVEL = 'WARN')  AS WARN_COUNT,
    COUNT_IF(LOG_LEVEL = 'ERROR') AS ERROR_COUNT,
    CASE
        WHEN COUNT_IF(LOG_LEVEL = 'ERROR') > 0 THEN 'RED'
        WHEN COUNT_IF(LOG_LEVEL = 'WARN')  > 0 THEN 'YELLOW'
        ELSE 'GREEN'
    END AS HEALTH_STATUS,
    MIN(LOGGED_AT) AS STARTED_AT,
    MAX(LOGGED_AT) AS ENDED_AT,
    DATEDIFF('second', MIN(LOGGED_AT), MAX(LOGGED_AT)) AS DURATION_SEC
FROM LOGS.RUN_LOG
GROUP BY 1
ORDER BY STARTED_AT DESC;

SELECT * FROM LOGS.BATCH_HEALTH;

-- ============================================================
-- PART C: Structured detail queries using VARIANT
-- ============================================================

-- Extract detail fields from the VARIANT column
SELECT
    RUN_ID,
    MESSAGE,
    DETAIL:rows_loaded::NUMBER    AS ROWS_LOADED,
    DETAIL:target::VARCHAR        AS TARGET_TABLE,
    DETAIL:batch_id::VARCHAR      AS BATCH_ID
FROM LOGS.RUN_LOG
WHERE DETAIL IS NOT NULL
  AND DETAIL:rows_loaded IS NOT NULL
ORDER BY LOGGED_AT DESC;

-- Quarantine detail
SELECT
    RUN_ID,
    MESSAGE,
    DETAIL:accepted::NUMBER       AS ACCEPTED,
    DETAIL:quarantined::NUMBER    AS QUARANTINED,
    DETAIL:batch_id::VARCHAR      AS BATCH_ID
FROM LOGS.RUN_LOG
WHERE DETAIL IS NOT NULL
  AND DETAIL:quarantined IS NOT NULL
ORDER BY LOGGED_AT DESC;

-- ============================================================
-- PART D: A reusable logging procedure
-- ============================================================

-- So any procedure can log consistently:
CREATE OR REPLACE PROCEDURE LOGS.LOG_EVENT(
    P_RUN_ID    VARCHAR,
    P_STEP      VARCHAR,
    P_LEVEL     VARCHAR,
    P_MESSAGE   VARCHAR,
    P_DETAIL    VARIANT
)
RETURNS VARCHAR
LANGUAGE SQL
AS
EXECUTE AS CALLER
BEGIN
    INSERT INTO LOGS.RUN_LOG (RUN_ID, STEP_NAME, LOG_LEVEL, MESSAGE, DETAIL)
    SELECT :P_RUN_ID, :P_STEP, UPPER(:P_LEVEL), :P_MESSAGE, :P_DETAIL;
    RETURN 'LOGGED';
END;

-- Test it
CALL LOGS.LOG_EVENT(
    'MANUAL-TEST-001',
    'LOGGING_EXERCISE',
    'INFO',
    'Testing the centralized logger from the lab',
    PARSE_JSON('{"test": true, "step": "03"}')
);

SELECT * FROM LOGS.RUN_LOG WHERE RUN_ID = 'MANUAL-TEST-001';

-- ============================================================
-- PART E: EXTENSION - Event table integration (discussion)
-- ============================================================

-- Snowflake Event Tables capture telemetry from stored procedures,
-- UDFs, and Snowpark code automatically. In production, you would:
--
-- 1. Set up an event table:
--    CREATE EVENT TABLE IF NOT EXISTS BUH_AUTOMATION_LAB.LOGS.PIPELINE_EVENTS;
--    ALTER DATABASE BUH_AUTOMATION_LAB SET EVENT_TABLE = 'BUH_AUTOMATION_LAB.LOGS.PIPELINE_EVENTS';
--
-- 2. Use SYSTEM$LOG() inside procedures:
--    SYSTEM$LOG_INFO('Import started for ' || table_name);
--    SYSTEM$LOG_WARN('Schema drift detected');
--    SYSTEM$LOG_ERROR('Validation failed: ' || error_msg);
--
-- 3. Query the event table:
--    SELECT * FROM BUH_AUTOMATION_LAB.LOGS.PIPELINE_EVENTS
--    WHERE RESOURCE_ATTRIBUTES['snow.executable.name'] = 'RUN_IMPORT';
--
-- The RUN_LOG approach we built is complementary - it gives you
-- structured business-level logging, while event tables give you
-- system-level telemetry.

-- ============================================================
-- PART F: EXTENSION - Alerting (discussion)
-- ============================================================

-- Snowflake Alerts can watch your log table and notify on errors:
--
-- CREATE ALERT IF NOT EXISTS LOGS.PIPELINE_ERROR_ALERT
--   WAREHOUSE = COMPUTE_WH
--   SCHEDULE = '5 MINUTE'
--   IF (EXISTS (
--     SELECT 1 FROM LOGS.RUN_LOG
--     WHERE LOG_LEVEL = 'ERROR'
--       AND LOGGED_AT > DATEADD('minute', -5, CURRENT_TIMESTAMP())
--   ))
--   THEN
--     CALL SYSTEM$SEND_EMAIL(
--       'lab_notifications',
--       'team@brownhealth.example',
--       'Pipeline Error Alert',
--       'Errors detected in the last 5 minutes. Check LOGS.RUN_LOG.'
--     );
--
-- This is not created during the lab because it requires a
-- notification integration, but the pattern is production-ready.

-- ============================================================
-- CHECKPOINT: You should see
--   - RUN_SUMMARY view with aggregated counts by hour/step/level
--   - BATCH_HEALTH view showing GREEN/YELLOW/RED per batch
--   - Structured detail extraction from VARIANT
--   - A reusable LOG_EVENT procedure
-- ============================================================
SELECT * FROM LOGS.BATCH_HEALTH;
