/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 06: Cleanup
  
  WARNING: This drops the entire lab database and roles.
           Make sure you have saved anything you want to keep.
=============================================================================*/

USE ROLE ACCOUNTADMIN;

-- Remove tag from warehouse before dropping database
ALTER WAREHOUSE COMPUTE_WH UNSET TAG BUH_HOL.GOVERNANCE.COST_CENTER;

-- Drop the database (removes all schemas, tables, dynamic tables, views, tags, policies)
DROP DATABASE IF EXISTS BUH_HOL;

-- Drop lab roles
DROP ROLE IF EXISTS BUH_LAB_CLINICIAN;
DROP ROLE IF EXISTS BUH_LAB_ANALYST;
DROP ROLE IF EXISTS BUH_LAB_ADMIN;

SELECT 'Lab cleanup complete. Database BUH_HOL and lab roles have been dropped.' AS STATUS;
