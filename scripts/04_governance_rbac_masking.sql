/*=============================================================================
  Brown University Health - Automation & Governance Hands-On Lab
  Script 04: Governance, RBAC & Masking
  
  GOAL: Apply reusable masking policies and row-access controls to
        protect sensitive patient data. Verify behavior across roles.
        Discuss classification and tagging as production extensions.
  
  TIME: ~20 minutes
  PREREQUISITE: Run 00-01 first (creates patient data)
  
  NOTE ON TRIAL ACCOUNTS:
    On a trial account your only user has ACCOUNTADMIN. Because
    IS_ROLE_IN_SESSION checks the full role hierarchy, switching to
    BUH_LAB_ANALYST still resolves BUH_LAB_ADMIN as TRUE (since
    ANALYST -> ADMIN -> ACCOUNTADMIN). To demonstrate masking
    properly, this script uses EXECUTE AS to simulate queries
    running as isolated roles.
=============================================================================*/

USE DATABASE BUH_AUTOMATION_LAB;
USE WAREHOUSE COMPUTE_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- PART A: See what is exposed today
-- ============================================================

-- All PII is visible to everyone right now
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, PHONE, EMAIL
FROM RAW.PATIENT_DIM
LIMIT 5;

-- ============================================================
-- PART B: Create reusable masking policies
-- ============================================================

USE SCHEMA BUH_AUTOMATION_LAB.GOVERNANCE;

-- Generic SSN mask - shows last 4 to clinicians, full to admin
CREATE OR REPLACE MASKING POLICY SSN_MASK AS (val VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN IS_ROLE_IN_SESSION('BUH_LAB_ADMIN') THEN val
        WHEN IS_ROLE_IN_SESSION('BUH_LAB_CLINICIAN') THEN '***-**-' || RIGHT(val, 4)
        ELSE '***-**-****'
    END
COMMENT = 'SSN masking policy. Full to ADMIN, last-4 to CLINICIAN, hidden to ANALYST. Owner: Lab Governance.';

-- Generic PII string mask - name, email, phone, address
CREATE OR REPLACE MASKING POLICY PII_STRING_MASK AS (val VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN IS_ROLE_IN_SESSION('BUH_LAB_ADMIN') THEN val
        WHEN IS_ROLE_IN_SESSION('BUH_LAB_CLINICIAN') THEN val
        ELSE '***MASKED***'
    END
COMMENT = 'PII string mask. Visible to ADMIN and CLINICIAN, masked for ANALYST. Owner: Lab Governance.';

-- ============================================================
-- PART C: Apply policies to patient data
-- ============================================================

ALTER TABLE RAW.PATIENT_DIM MODIFY COLUMN SSN
    SET MASKING POLICY GOVERNANCE.SSN_MASK;

ALTER TABLE RAW.PATIENT_DIM MODIFY COLUMN PAT_FIRST_NAME
    SET MASKING POLICY GOVERNANCE.PII_STRING_MASK;

ALTER TABLE RAW.PATIENT_DIM MODIFY COLUMN PAT_LAST_NAME
    SET MASKING POLICY GOVERNANCE.PII_STRING_MASK;

ALTER TABLE RAW.PATIENT_DIM MODIFY COLUMN PHONE
    SET MASKING POLICY GOVERNANCE.PII_STRING_MASK;

ALTER TABLE RAW.PATIENT_DIM MODIFY COLUMN EMAIL
    SET MASKING POLICY GOVERNANCE.PII_STRING_MASK;

ALTER TABLE RAW.PATIENT_DIM MODIFY COLUMN ADDRESS_LINE_1
    SET MASKING POLICY GOVERNANCE.PII_STRING_MASK;

-- ============================================================
-- PART D: Test across roles using POLICY_CONTEXT
-- ============================================================

-- On a trial account your user owns ACCOUNTADMIN, so USE ROLE
-- BUH_LAB_ANALYST still inherits BUH_LAB_ADMIN. To see masking
-- in action we use EXECUTE USING POLICY_CONTEXT which tells
-- Snowflake to evaluate policies AS IF a different set of roles
-- were active.

-- As ADMIN - should see everything
EXECUTE USING POLICY_CONTEXT(
    CURRENT_ROLE => 'BUH_LAB_ADMIN'
)
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, PHONE, EMAIL
FROM BUH_AUTOMATION_LAB.RAW.PATIENT_DIM LIMIT 3;

-- As CLINICIAN - should see names/phone/email, SSN last-4 only
EXECUTE USING POLICY_CONTEXT(
    CURRENT_ROLE => 'BUH_LAB_CLINICIAN'
)
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, PHONE, EMAIL
FROM BUH_AUTOMATION_LAB.RAW.PATIENT_DIM LIMIT 3;

-- As ANALYST - should see masked names, masked SSN, masked phone/email
EXECUTE USING POLICY_CONTEXT(
    CURRENT_ROLE => 'BUH_LAB_ANALYST'
)
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, PHONE, EMAIL
FROM BUH_AUTOMATION_LAB.RAW.PATIENT_DIM LIMIT 3;

-- ============================================================
-- PART E: Row-Access Policy example
-- ============================================================

USE SCHEMA BUH_AUTOMATION_LAB.GOVERNANCE;

-- Clinicians should only see encounters from their department.
-- For the lab, we simulate this with a mapping table.

CREATE OR REPLACE TABLE GOVERNANCE.ROLE_DEPARTMENT_ACCESS (
    ROLE_NAME    VARCHAR(50),
    DEPARTMENT   VARCHAR(50)
);

INSERT INTO GOVERNANCE.ROLE_DEPARTMENT_ACCESS VALUES
('BUH_LAB_CLINICIAN', 'Cardiology'),
('BUH_LAB_CLINICIAN', 'Primary Care');

-- The row-access policy checks the mapping table
CREATE OR REPLACE ROW ACCESS POLICY GOVERNANCE.DEPARTMENT_ROW_FILTER
AS (department_val VARCHAR) RETURNS BOOLEAN ->
    IS_ROLE_IN_SESSION('BUH_LAB_ADMIN')
    OR IS_ROLE_IN_SESSION('BUH_LAB_ANALYST')
    OR EXISTS (
        SELECT 1 FROM GOVERNANCE.ROLE_DEPARTMENT_ACCESS
        WHERE ROLE_NAME = 'BUH_LAB_CLINICIAN'
          AND DEPARTMENT = department_val
          AND IS_ROLE_IN_SESSION('BUH_LAB_CLINICIAN')
    )
COMMENT = 'Row filter by department. ADMIN/ANALYST see all, CLINICIAN sees mapped departments.';

-- Apply to encounter table
ALTER TABLE RAW.ENCOUNTER_FACT ADD ROW ACCESS POLICY
    GOVERNANCE.DEPARTMENT_ROW_FILTER ON (DEPARTMENT);

-- Test: ADMIN sees all 10 encounters
EXECUTE USING POLICY_CONTEXT(
    CURRENT_ROLE => 'BUH_LAB_ADMIN'
)
SELECT ENCOUNTER_ID, DEPARTMENT, ENCOUNTER_TYPE
FROM BUH_AUTOMATION_LAB.RAW.ENCOUNTER_FACT
ORDER BY ENCOUNTER_ID;

-- Test: CLINICIAN sees only Cardiology and Primary Care (4 rows)
EXECUTE USING POLICY_CONTEXT(
    CURRENT_ROLE => 'BUH_LAB_CLINICIAN'
)
SELECT ENCOUNTER_ID, DEPARTMENT, ENCOUNTER_TYPE
FROM BUH_AUTOMATION_LAB.RAW.ENCOUNTER_FACT
ORDER BY ENCOUNTER_ID;

-- ============================================================
-- PART F: Audit what policies exist
-- ============================================================

-- List all masking policies in the database
SHOW MASKING POLICIES IN DATABASE BUH_AUTOMATION_LAB;

-- List all row access policies
SHOW ROW ACCESS POLICIES IN DATABASE BUH_AUTOMATION_LAB;

-- Check which columns have policies applied
SELECT
    POLICY_NAME,
    POLICY_KIND,
    REF_ENTITY_NAME,
    REF_COLUMN_NAME
FROM TABLE(BUH_AUTOMATION_LAB.INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_NAME => 'BUH_AUTOMATION_LAB.RAW.PATIENT_DIM',
    REF_ENTITY_DOMAIN => 'TABLE'
));

-- ============================================================
-- PART G: EXTENSION - Tags and classification (discussion)
-- ============================================================

-- In production, you would use Snowflake's built-in classification
-- to automatically detect PII columns, then apply tag-based masking:
--
-- Step 1: Classify
--   CALL SYSTEM$CLASSIFY('BUH_AUTOMATION_LAB.RAW.PATIENT_DIM',
--                         {'auto_tag': true});
--
-- Step 2: Create tag-based masking policy
--   CREATE TAG IF NOT EXISTS GOVERNANCE.PII_TYPE;
--   ALTER TAG GOVERNANCE.PII_TYPE SET MASKING POLICY GOVERNANCE.PII_STRING_MASK;
--
-- Step 3: Tags travel with columns - if you create a view or CTAS,
--         the policy follows automatically.
--
-- This is not run during the lab because:
--   - Classification requires specific account configuration
--   - Tag-based masking requires tags to be set first
-- But the pattern is the production-recommended approach.

-- ============================================================
-- PART H: Verify policies travel to downstream tables
-- ============================================================

-- Important: Masking policies applied to a base table do NOT
-- automatically propagate to a CTAS copy. The CURATED tables
-- created by RUN_IMPORT are unprotected unless policies are
-- also applied there.

-- Check: CURATED.DIM_PATIENT has NO masking (if it exists)
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN
FROM CURATED.DIM_PATIENT LIMIT 3;

-- To protect CURATED tables too, either:
-- 1. Apply the same policies to CURATED tables (manual)
-- 2. Use secure views that reference the base table (policies apply)
-- 3. Use tag-based masking (tags propagate through lineage)

-- Example: Secure view approach
CREATE OR REPLACE SECURE VIEW CURATED.V_DIM_PATIENT AS
SELECT * FROM RAW.PATIENT_DIM;

-- Now test - the view inherits the base table's policies
EXECUTE USING POLICY_CONTEXT(
    CURRENT_ROLE => 'BUH_LAB_ANALYST'
)
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN
FROM BUH_AUTOMATION_LAB.CURATED.V_DIM_PATIENT LIMIT 3;

-- ============================================================
-- CHECKPOINT: You should see
--   - SSN masked differently per role
--   - PII fields masked for analyst, visible for clinician
--   - Row-access filtering encounters by department for clinician
--   - Policy audit queries returning applied policies
--   - Secure view inheriting base table masking
-- ============================================================
