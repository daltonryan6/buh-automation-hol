/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 03: Power BI, Iceberg Tables & Microsoft Fabric
  
  GOAL: Understand the connection options between Snowflake and
        Power BI, how Iceberg tables work for a gold/datamart
        layer, and the cost and governance implications of Fabric.
  
  TIME: ~25 minutes (guided walkthrough + hands-on Iceberg)
  PREREQUISITE: Run 00_setup.sql and 02_dynamic_tables.sql first
  
  NOTE: This module includes a hands-on Iceberg section that runs
        on a trial account, and a walkthrough section on Power BI
        and Fabric that uses discussion and reference material.
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE COMPUTE_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- PART A: Power BI connection options (walkthrough)
-- ============================================================

-- There are three primary ways to connect Power BI to Snowflake:
--
-- OPTION 1: DirectQuery
-- -------------------------------------------------------
-- - Power BI sends SQL to Snowflake at query time
-- - Data stays in Snowflake, not copied into Power BI
-- - Pro: Always fresh, no import schedule needed
-- - Con: Every dashboard interaction runs a Snowflake query
--        (warehouse must be running, costs credits)
-- - Con: Performance depends on query complexity and warehouse size
-- - Best for: Operational dashboards with moderate concurrency
--
-- OPTION 2: Import Mode
-- -------------------------------------------------------
-- - Power BI extracts data into its own in-memory engine
-- - Scheduled refresh (e.g. every hour or daily)
-- - Pro: Fast dashboard performance (data is local to Power BI)
-- - Pro: Snowflake warehouse only runs during refresh window
-- - Con: Data is stale between refreshes
-- - Con: Dataset size limits in Power BI Pro (1GB) / Premium (varies)
-- - Best for: Executive/strategic dashboards refreshed daily
--
-- OPTION 3: Snowflake + OneLake + Direct Lake (Fabric)
-- -------------------------------------------------------
-- - Snowflake writes Iceberg tables to Microsoft OneLake
-- - Power BI reads Parquet files via Direct Lake mode
-- - Pro: No Snowflake warehouse needed for BI reads
-- - Pro: Data is open format (Iceberg/Parquet), not locked in
-- - Con: Requires Fabric capacity (F SKU or higher)
-- - Con: Setup complexity (external volume, OneLake integration)
-- - Best for: When Microsoft is pushing Fabric adoption and you
--             want to minimize Snowflake compute for BI workloads

-- ============================================================
-- PART B: Fabric consumption - what to watch for
-- ============================================================

-- Louis's concern: "We are very suspicious of fabric overconsumption"
--
-- Key cost drivers in Fabric:
--
-- 1. CAPACITY UNITS (CUs)
--    - Fabric uses a single pool of compute (F2, F4, F8... F2048)
--    - ALL Fabric workloads share this pool: Power BI, Dataflow,
--      Spark, SQL endpoint, etc.
--    - If the pool is exhausted, workloads queue or throttle
--
-- 2. DIRECT LAKE reads
--    - Direct Lake reads Parquet from OneLake at query time
--    - Consumes CUs from the same pool
--    - Large/complex models can burn capacity fast
--    - No separate "per-query" billing like Snowflake
--
-- 3. SNOWFLAKE-SIDE COSTS
--    - Writing Iceberg tables to OneLake: Snowflake compute
--    - Refreshing dynamic tables that feed Iceberg: Snowflake compute
--    - Storage: Iceberg files in OneLake count toward Fabric storage
--    - But: NO Snowflake warehouse needed for Power BI reads
--
-- CHEAPEST PATH for Power BI + Snowflake:
--   a. Keep your pipeline (RAW -> CURATED -> GOLD) in Snowflake
--      using dynamic tables (Script 02)
--   b. Write only the GOLD layer out as Iceberg to OneLake
--   c. Power BI reads from Direct Lake - no Snowflake queries
--   d. Snowflake warehouse auto-suspends between refreshes
--   e. Size your Fabric capacity for the BI read load only

-- ============================================================
-- PART C: Iceberg tables - hands-on
-- ============================================================

-- Iceberg tables use the same SQL as regular Snowflake tables,
-- but the data is stored in open Parquet format with Iceberg
-- metadata. Any engine that reads Iceberg can access the data.

-- Create a managed Iceberg table (Snowflake-managed storage)
-- This works on any account, no external volume needed.

CREATE OR REPLACE ICEBERG TABLE BUH_HOL.GOLD.DEPT_DASHBOARD_ICEBERG
  CATALOG = 'SNOWFLAKE'
  EXTERNAL_VOLUME = ''
  BASE_LOCATION = 'dept_dashboard/'
AS
SELECT
    e.DEPARTMENT,
    COUNT(DISTINCT e.ENCOUNTER_ID) AS ENCOUNTER_COUNT,
    COUNT(DISTINCT e.PAT_ID)       AS UNIQUE_PATIENTS,
    AVG(e.TOTAL_CHARGES)           AS AVG_CHARGES,
    SUM(e.TOTAL_CHARGES)           AS TOTAL_CHARGES
FROM BUH_HOL.RAW.ENCOUNTER_FACT e
GROUP BY e.DEPARTMENT;

-- Query it just like a regular table
SELECT * FROM BUH_HOL.GOLD.DEPT_DASHBOARD_ICEBERG ORDER BY TOTAL_CHARGES DESC;

-- See the Iceberg metadata
DESCRIBE TABLE BUH_HOL.GOLD.DEPT_DASHBOARD_ICEBERG;

-- ============================================================
-- PART D: Iceberg for OneLake (walkthrough)
-- ============================================================

-- To write Iceberg tables directly to Microsoft OneLake
-- (the pattern Microsoft is recommending), you would:
--
-- 1. Create an external volume pointing to OneLake:
--
--    CREATE EXTERNAL VOLUME onelake_vol
--    STORAGE_LOCATIONS = (
--      (
--        NAME = 'fabric_onelake'
--        STORAGE_PROVIDER = 'AZURE'
--        STORAGE_BASE_URL = 'azure://onelake.dfs.fabric.microsoft.com/<workspace-id>/<item-id>/SnowflakeVolume'
--        AZURE_TENANT_ID = '<your-fabric-tenant-id>'
--      )
--    );
--
-- 2. Create an Iceberg table that uses OneLake:
--
--    CREATE ICEBERG TABLE GOLD.PATIENT_SUMMARY_ICEBERG
--      CATALOG = 'SNOWFLAKE'
--      EXTERNAL_VOLUME = 'onelake_vol'
--      BASE_LOCATION = 'patient_summary/'
--    AS SELECT * FROM GOLD.PATIENT_ENCOUNTER_SUMMARY;
--
-- 3. Power BI connects via Direct Lake to the OneLake path
--    No Snowflake warehouse runs when Power BI queries the data.
--
-- 4. Refresh pattern:
--    - Dynamic tables keep GOLD fresh in Snowflake
--    - A task or schedule recreates the Iceberg table in OneLake
--    - Power BI sees the latest data without warehouse cost

-- ============================================================
-- PART E: Will Iceberg tables show in Purview?
-- ============================================================

-- YES, with caveats:
--
-- Microsoft Purview can scan Snowflake accounts directly.
-- Purview discovers: databases, schemas, tables (including Iceberg),
-- views, stored procedures, functions, pipes, stages, streams, tasks.
-- Purview also extracts lineage for tables, views, and streams.
--
-- For Iceberg tables written to OneLake:
-- - Purview can scan the Snowflake side (sees the Iceberg table definition)
-- - Purview can also see the Parquet files in OneLake via Fabric scanning
-- - Sensitivity labels applied in Purview propagate to Fabric items
--
-- What Purview does NOT do:
-- - It does not automatically pick up Snowflake tags as Purview labels
-- - Snowflake tags and Purview sensitivity labels are separate systems
-- - You would need to map Snowflake classification results to Purview
--   labels via a sync process or manual alignment
--
-- The practical answer: If your governance team uses Purview,
-- scanning Snowflake is straightforward. But Snowflake tags and
-- Purview labels are not the same thing and do not auto-sync.

-- ============================================================
-- PART F: Snowflake default tables vs Iceberg - when to use each
-- ============================================================

-- Microsoft is suggesting: "host your gold layer in Iceberg tables"
--
-- Here is the decision framework:
--
-- USE SNOWFLAKE DEFAULT TABLES when:
--   - Data stays within Snowflake for analytics, AI, sharing
--   - You want the fastest query performance (Snowflake-native)
--   - Dynamic tables, streams, tasks, time travel all work natively
--   - You do not need other engines to read the data
--
-- USE ICEBERG TABLES when:
--   - Other engines need to read the data (Fabric, Spark, Trino)
--   - You want data in open format (Parquet) for portability
--   - You are writing to OneLake for Power BI Direct Lake
--   - You want to avoid vendor lock-in at the storage layer
--
-- HYBRID APPROACH (recommended for BUH):
--   RAW layer    -> Snowflake default tables (fast ingest, time travel)
--   CURATED layer -> Snowflake default tables (dynamic tables, joins)
--   GOLD layer   -> Iceberg tables in OneLake (Power BI reads here)
--
-- This gives you the best of both: Snowflake performance for
-- pipeline processing, open format for BI consumption.

-- ============================================================
-- CHECKPOINT
-- ============================================================

-- You should understand:
--   1. Three Power BI connection options and when to use each
--   2. Why Fabric CU overconsumption happens and how to limit it
--   3. How Iceberg tables work in Snowflake (same SQL, open format)
--   4. The Purview integration picture (scans work, labels are separate)
--   5. When to use Snowflake tables vs Iceberg vs both

SELECT * FROM BUH_HOL.GOLD.DEPT_DASHBOARD_ICEBERG ORDER BY TOTAL_CHARGES DESC;
