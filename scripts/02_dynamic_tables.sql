/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 02: Dynamic Tables
  
  GOAL: Build a multi-layer pipeline using dynamic tables that
        automatically refresh when source data changes. Replace
        manual ETL scripts with declarative transformations.
  
  TIME: ~30 minutes
  PREREQUISITE: Run 00_setup.sql first
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE COMPUTE_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- PART A: The problem - manual pipelines
-- ============================================================

-- Today you might run a series of CTAS or INSERT/MERGE statements
-- to build curated and gold tables. Each one is a script you
-- schedule, monitor, and fix when it breaks.

-- Dynamic tables flip this: you declare WHAT the result should
-- look like, and Snowflake figures out WHEN to refresh it.

-- ============================================================
-- PART B: Build a CURATED layer with dynamic tables
-- ============================================================

-- CURATED.DIM_PATIENT - clean patient demographics
-- TARGET_LAG = '1 minute' means Snowflake will refresh this
-- within 1 minute of a change to the source table.

CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CURATED.DIM_PATIENT
  TARGET_LAG = '1 minute'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    PAT_ID,
    PAT_MRN,
    INITCAP(PAT_FIRST_NAME) AS FIRST_NAME,
    INITCAP(PAT_LAST_NAME)  AS LAST_NAME,
    BIRTH_DATE,
    DATEDIFF('year', BIRTH_DATE, CURRENT_DATE()) AS AGE,
    SSN,
    ADDRESS_LINE_1,
    CITY,
    STATE,
    ZIP_CODE,
    PHONE,
    EMAIL,
    PRIM_LANGUAGE,
    GENDER,
    LOAD_TS AS SOURCE_LOADED_AT
FROM BUH_HOL.RAW.PATIENT_DIM;

-- CURATED.DIM_PROVIDER - clean provider dimension
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CURATED.DIM_PROVIDER
  TARGET_LAG = '1 minute'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    PROV_ID,
    PROV_NAME,
    SPECIALTY,
    DEPARTMENT,
    NPI,
    ACTIVE
FROM BUH_HOL.RAW.PROVIDER_DIM;

-- CURATED.FACT_ENCOUNTER - enriched encounters
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CURATED.FACT_ENCOUNTER
  TARGET_LAG = '1 minute'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    e.ENCOUNTER_ID,
    e.PAT_ID,
    e.ENCOUNTER_TYPE,
    e.ADMIT_DATE,
    e.DISCHARGE_DATE,
    DATEDIFF('day', e.ADMIT_DATE, COALESCE(e.DISCHARGE_DATE, CURRENT_DATE())) AS LENGTH_OF_STAY,
    e.DEPARTMENT,
    e.ATTENDING_PROV_ID,
    p.PROV_NAME AS ATTENDING_PROVIDER,
    p.SPECIALTY AS PROVIDER_SPECIALTY,
    e.PRIMARY_DX_CODE,
    e.PRIMARY_DX_NAME,
    e.ENCOUNTER_STATUS,
    e.TOTAL_CHARGES,
    e.LOAD_TS AS SOURCE_LOADED_AT
FROM BUH_HOL.RAW.ENCOUNTER_FACT e
LEFT JOIN BUH_HOL.RAW.PROVIDER_DIM p ON e.ATTENDING_PROV_ID = p.PROV_ID;

-- CURATED.FACT_LAB_RESULTS - enriched lab results with flags
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.CURATED.FACT_LAB_RESULTS
  TARGET_LAG = '1 minute'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    r.RESULT_ID,
    r.ENCOUNTER_ID,
    r.PAT_ID,
    r.TEST_CODE,
    r.TEST_NAME,
    r.RESULT_VALUE,
    r.RESULT_UNIT,
    r.REFERENCE_LOW,
    r.REFERENCE_HIGH,
    CASE
        WHEN r.RESULT_VALUE > r.REFERENCE_HIGH THEN 'HIGH'
        WHEN r.RESULT_VALUE < r.REFERENCE_LOW  THEN 'LOW'
        ELSE 'NORMAL'
    END AS ABNORMAL_FLAG,
    r.RESULT_DATE
FROM BUH_HOL.RAW.LAB_RESULTS r;

-- ============================================================
-- PART C: Build a GOLD layer on top of CURATED
-- ============================================================

-- Dynamic tables can chain - GOLD reads from CURATED,
-- which reads from RAW. The whole pipeline refreshes
-- automatically when RAW changes.

-- GOLD.PATIENT_ENCOUNTER_SUMMARY
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.GOLD.PATIENT_ENCOUNTER_SUMMARY
  TARGET_LAG = '1 minute'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    p.PAT_ID,
    p.PAT_MRN,
    p.FIRST_NAME || ' ' || p.LAST_NAME AS PATIENT_NAME,
    p.AGE,
    p.GENDER,
    COUNT(e.ENCOUNTER_ID)                     AS TOTAL_ENCOUNTERS,
    COUNT_IF(e.ENCOUNTER_TYPE = 'Inpatient')  AS INPATIENT_COUNT,
    COUNT_IF(e.ENCOUNTER_TYPE = 'Emergency')  AS ED_VISITS,
    SUM(e.TOTAL_CHARGES)                      AS TOTAL_CHARGES,
    MAX(e.ADMIT_DATE)                         AS LAST_VISIT_DATE,
    LISTAGG(DISTINCT e.DEPARTMENT, ', ')
        WITHIN GROUP (ORDER BY e.DEPARTMENT)  AS DEPARTMENTS_SEEN
FROM BUH_HOL.CURATED.DIM_PATIENT p
LEFT JOIN BUH_HOL.CURATED.FACT_ENCOUNTER e ON p.PAT_ID = e.PAT_ID
GROUP BY p.PAT_ID, p.PAT_MRN, p.FIRST_NAME, p.LAST_NAME, p.AGE, p.GENDER;

-- GOLD.DEPARTMENT_DASHBOARD
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.GOLD.DEPARTMENT_DASHBOARD
  TARGET_LAG = '1 minute'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    e.DEPARTMENT,
    COUNT(DISTINCT e.ENCOUNTER_ID)            AS ENCOUNTER_COUNT,
    COUNT(DISTINCT e.PAT_ID)                  AS UNIQUE_PATIENTS,
    COUNT_IF(e.ENCOUNTER_TYPE = 'Inpatient')  AS INPATIENT_COUNT,
    COUNT_IF(e.ENCOUNTER_TYPE = 'Emergency')  AS ED_COUNT,
    AVG(e.LENGTH_OF_STAY)                     AS AVG_LOS,
    SUM(e.TOTAL_CHARGES)                      AS TOTAL_CHARGES,
    AVG(e.TOTAL_CHARGES)                      AS AVG_CHARGES
FROM BUH_HOL.CURATED.FACT_ENCOUNTER e
GROUP BY e.DEPARTMENT;

-- GOLD.ABNORMAL_RESULTS_SUMMARY
CREATE OR REPLACE DYNAMIC TABLE BUH_HOL.GOLD.ABNORMAL_RESULTS_SUMMARY
  TARGET_LAG = '1 minute'
  WAREHOUSE = COMPUTE_WH
AS
SELECT
    lr.PAT_ID,
    p.FIRST_NAME || ' ' || p.LAST_NAME AS PATIENT_NAME,
    lr.TEST_NAME,
    lr.RESULT_VALUE,
    lr.RESULT_UNIT,
    lr.REFERENCE_HIGH,
    lr.ABNORMAL_FLAG,
    lr.RESULT_DATE,
    e.DEPARTMENT,
    e.ATTENDING_PROVIDER
FROM BUH_HOL.CURATED.FACT_LAB_RESULTS lr
JOIN BUH_HOL.CURATED.FACT_ENCOUNTER e ON lr.ENCOUNTER_ID = e.ENCOUNTER_ID
JOIN BUH_HOL.CURATED.DIM_PATIENT p ON lr.PAT_ID = p.PAT_ID
WHERE lr.ABNORMAL_FLAG != 'NORMAL';

-- ============================================================
-- PART D: Verify the pipeline
-- ============================================================

-- Check that dynamic tables are populating
SELECT * FROM BUH_HOL.CURATED.DIM_PATIENT LIMIT 5;
SELECT * FROM BUH_HOL.GOLD.PATIENT_ENCOUNTER_SUMMARY ORDER BY TOTAL_CHARGES DESC;
SELECT * FROM BUH_HOL.GOLD.DEPARTMENT_DASHBOARD ORDER BY TOTAL_CHARGES DESC;
SELECT * FROM BUH_HOL.GOLD.ABNORMAL_RESULTS_SUMMARY ORDER BY RESULT_DATE;

-- ============================================================
-- PART E: Watch it refresh automatically
-- ============================================================

-- Insert a new patient into the RAW layer
INSERT INTO BUH_HOL.RAW.PATIENT_DIM (PAT_ID,PAT_MRN,PAT_FIRST_NAME,PAT_LAST_NAME,BIRTH_DATE,SSN,ADDRESS_LINE_1,CITY,STATE,ZIP_CODE,PHONE,EMAIL,PRIM_LANGUAGE,GENDER) VALUES
('P100009','MRN-900009','Elena','Vasquez','2001-02-14','999-00-1111','500 Atwells Ave','Providence','RI','02909','401-555-0109','evasquez@example.com','Spanish','Female');

-- Insert an encounter for the new patient
INSERT INTO BUH_HOL.RAW.ENCOUNTER_FACT VALUES
('E200011','P100009','Emergency','2024-10-25','2024-10-25','Emergency Dept','PROV-003','R10.9','Unspecified abdominal pain','Discharged',3200.00,CURRENT_TIMESTAMP());

-- Wait ~1 minute, then check - the new patient should appear
-- in CURATED and GOLD tables automatically

-- Check the CURATED layer
SELECT * FROM BUH_HOL.CURATED.DIM_PATIENT WHERE PAT_ID = 'P100009';

-- Check the GOLD layer
SELECT * FROM BUH_HOL.GOLD.PATIENT_ENCOUNTER_SUMMARY WHERE PAT_ID = 'P100009';

-- Check department dashboard updated
SELECT * FROM BUH_HOL.GOLD.DEPARTMENT_DASHBOARD
WHERE DEPARTMENT = 'Emergency Dept';

-- ============================================================
-- PART F: Monitor dynamic table health
-- ============================================================

-- Check refresh history
SELECT
    NAME,
    STATE,
    STATE_MESSAGE,
    REFRESH_START_TIME,
    REFRESH_END_TIME,
    DATEDIFF('second', REFRESH_START_TIME, REFRESH_END_TIME) AS REFRESH_SECONDS
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
ORDER BY REFRESH_START_TIME DESC
LIMIT 20;

-- Check the graph dependencies
SELECT
    NAME,
    TARGET_LAG,
    SCHEDULING_STATE
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_GRAPH_HISTORY())
WHERE DATABASE_NAME = 'BUH_HOL'
ORDER BY NAME;

-- ============================================================
-- PART G: Key takeaways
-- ============================================================

-- 1. DECLARATIVE: You write the SELECT, Snowflake handles the schedule
-- 2. CHAINED: GOLD reads CURATED reads RAW - the whole graph refreshes
-- 3. INCREMENTAL: Snowflake only processes changed data when possible
-- 4. OBSERVABLE: Built-in refresh history and graph monitoring
-- 5. TARGET_LAG: You set how fresh data needs to be, not when to run

-- In production, you would set TARGET_LAG based on business needs:
--   '1 minute'  = near real-time dashboards
--   '15 minutes' = operational reporting
--   '1 hour'    = standard analytics
--   DOWNSTREAM  = only refresh when a downstream table needs it

-- ============================================================
-- CHECKPOINT
-- ============================================================

-- You should see:
--   - 4 dynamic tables in CURATED (DIM_PATIENT, DIM_PROVIDER,
--     FACT_ENCOUNTER, FACT_LAB_RESULTS)
--   - 3 dynamic tables in GOLD (PATIENT_ENCOUNTER_SUMMARY,
--     DEPARTMENT_DASHBOARD, ABNORMAL_RESULTS_SUMMARY)
--   - New patient P100009 appearing in all layers after refresh
--   - Refresh history showing successful refreshes

SELECT 'CURATED.DIM_PATIENT' AS DT, COUNT(*) AS ROWS FROM BUH_HOL.CURATED.DIM_PATIENT
UNION ALL SELECT 'CURATED.FACT_ENCOUNTER', COUNT(*) FROM BUH_HOL.CURATED.FACT_ENCOUNTER
UNION ALL SELECT 'CURATED.FACT_LAB_RESULTS', COUNT(*) FROM BUH_HOL.CURATED.FACT_LAB_RESULTS
UNION ALL SELECT 'GOLD.PATIENT_ENCOUNTER_SUMMARY', COUNT(*) FROM BUH_HOL.GOLD.PATIENT_ENCOUNTER_SUMMARY
UNION ALL SELECT 'GOLD.DEPARTMENT_DASHBOARD', COUNT(*) FROM BUH_HOL.GOLD.DEPARTMENT_DASHBOARD
UNION ALL SELECT 'GOLD.ABNORMAL_RESULTS_SUMMARY', COUNT(*) FROM BUH_HOL.GOLD.ABNORMAL_RESULTS_SUMMARY
ORDER BY DT;
