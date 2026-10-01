/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 05: Bringing It Together
  
  GOAL: See how workspaces, dynamic tables, Iceberg, and tags
        form one coherent architecture.
  
  TIME: ~10 minutes
  PREREQUISITE: Run 00-04 first
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE COMPUTE_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- THE FULL PICTURE
-- ============================================================

-- What you built in this lab:
--
--  [Git Repo] --> [Snowflake Workspace]
--       |
--       v
--  RAW (default tables, Clarity extracts)
--       |  dynamic tables auto-refresh
--       v
--  CURATED (DIM_PATIENT, FACT_ENCOUNTER, FACT_LAB_RESULTS)
--       |  dynamic tables auto-refresh
--       v
--  GOLD (PATIENT_ENCOUNTER_SUMMARY, DEPT_DASHBOARD, ABNORMAL_RESULTS)
--       |
--       +--> Snowflake default tables (fast analytics, AI, sharing)
--       |
--       +--> Iceberg tables in OneLake (Power BI Direct Lake)
--
--  GOVERNANCE layer (tags, masking policies, classification)
--  applies across ALL layers.

-- ============================================================
-- VERIFY: End-to-end data flow
-- ============================================================

-- RAW layer: source data
SELECT 'RAW.PATIENT_DIM' AS LAYER, COUNT(*) AS ROWS FROM BUH_HOL.RAW.PATIENT_DIM
UNION ALL SELECT 'RAW.ENCOUNTER_FACT', COUNT(*) FROM BUH_HOL.RAW.ENCOUNTER_FACT
UNION ALL SELECT 'RAW.LAB_RESULTS', COUNT(*) FROM BUH_HOL.RAW.LAB_RESULTS

-- CURATED layer: cleaned + enriched via dynamic tables
UNION ALL SELECT 'CURATED.DIM_PATIENT', COUNT(*) FROM BUH_HOL.CURATED.DIM_PATIENT
UNION ALL SELECT 'CURATED.FACT_ENCOUNTER', COUNT(*) FROM BUH_HOL.CURATED.FACT_ENCOUNTER
UNION ALL SELECT 'CURATED.FACT_LAB_RESULTS', COUNT(*) FROM BUH_HOL.CURATED.FACT_LAB_RESULTS

-- GOLD layer: aggregated, ready for Power BI
UNION ALL SELECT 'GOLD.PATIENT_ENCOUNTER_SUMMARY', COUNT(*) FROM BUH_HOL.GOLD.PATIENT_ENCOUNTER_SUMMARY
UNION ALL SELECT 'GOLD.DEPARTMENT_DASHBOARD', COUNT(*) FROM BUH_HOL.GOLD.DEPARTMENT_DASHBOARD
UNION ALL SELECT 'GOLD.ABNORMAL_RESULTS_SUMMARY', COUNT(*) FROM BUH_HOL.GOLD.ABNORMAL_RESULTS_SUMMARY

ORDER BY LAYER;

-- ============================================================
-- VERIFY: Governance coverage
-- ============================================================

-- How many columns are tagged?
SELECT
    TAG_NAME,
    COUNT(*) AS TAGGED_COLUMNS
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE OBJECT_DATABASE = 'BUH_HOL'
  AND DOMAIN = 'COLUMN'
GROUP BY TAG_NAME
ORDER BY TAG_NAME;

-- How many masking policies are applied?
SHOW MASKING POLICIES IN DATABASE BUH_HOL;

-- ============================================================
-- NEXT STEPS FOR YOUR ENVIRONMENT
-- ============================================================

-- 1. GIT WORKSPACES
--    - Connect your team's GitLab/GitHub to Snowflake
--    - Store all SQL in version control
--    - Use Cortex Code for AI-assisted development
--
-- 2. DYNAMIC TABLES
--    - Replace scheduled CTAS/MERGE scripts with dynamic tables
--    - Set TARGET_LAG based on business freshness requirements
--    - Monitor via DYNAMIC_TABLE_REFRESH_HISTORY
--
-- 3. POWER BI / ICEBERG
--    - Set up the OneLake external volume
--    - Write GOLD layer as Iceberg tables
--    - Connect Power BI via Direct Lake
--    - Right-size Fabric capacity to avoid overconsumption
--
-- 4. TAGS & GOVERNANCE
--    - Define your tag taxonomy (PII_TYPE, SENSITIVITY, DATA_DOMAIN)
--    - Run SYSTEM$CLASSIFY to auto-detect PII
--    - Attach masking policies to tags (not individual columns)
--    - Align Snowflake tags with Purview labels if using both
--
-- 5. COST MANAGEMENT
--    - Tag warehouses with COST_CENTER for chargeback
--    - Use XSMALL warehouses with AUTO_SUSPEND = 60
--    - Dynamic tables consolidate compute (no scattered schedules)
--    - Iceberg to OneLake eliminates BI query cost in Snowflake
