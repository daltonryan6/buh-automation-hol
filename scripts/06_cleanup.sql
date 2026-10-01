/*=============================================================================
  Brown University Health - Automation & Governance Hands-On Lab
  Script 06: Cleanup
  
  Run this when you are finished with the lab to remove all
  objects created during the session.
  
  WARNING: This drops the entire lab database and roles.
           Make sure you have saved anything you want to keep.
=============================================================================*/

USE ROLE ACCOUNTADMIN;

-- Drop the database (removes all schemas, tables, views, procedures)
DROP DATABASE IF EXISTS BUH_AUTOMATION_LAB;

-- Drop lab roles
DROP ROLE IF EXISTS BUH_LAB_CLINICIAN;
DROP ROLE IF EXISTS BUH_LAB_ANALYST;
DROP ROLE IF EXISTS BUH_LAB_ADMIN;

-- Confirm cleanup
SELECT 'Lab cleanup complete. Database BUH_AUTOMATION_LAB and lab roles have been dropped.' AS STATUS;
