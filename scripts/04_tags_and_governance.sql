/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 04: Tags, Sensitivity Labels & Governance
  
  GOAL: Understand Snowflake tags - where they are applied, why
        they matter, and how they connect to sensitivity labels,
        masking policies, and Microsoft Purview.
  
  TIME: ~25 minutes
  PREREQUISITE: Run 00_setup.sql and 02_dynamic_tables.sql first
=============================================================================*/

USE DATABASE BUH_HOL;
USE WAREHOUSE COMPUTE_WH;
USE ROLE ACCOUNTADMIN;

-- ============================================================
-- PART A: What are tags and where do they apply?
-- ============================================================

-- Tags are key-value metadata you attach to Snowflake objects.
-- They answer: "What KIND of thing is this?"

-- WHERE CAN TAGS BE APPLIED?
--   - Warehouses     (e.g., cost_center = 'Research')
--   - Databases      (e.g., data_domain = 'Clinical')
--   - Schemas        (e.g., data_layer = 'RAW')
--   - Tables / Views (e.g., contains_phi = 'Yes')
--   - Columns        (e.g., pii_type = 'SSN')
--
-- Tags CANNOT be applied to:
--   - Individual rows
--   - Stages or file formats
--   - Users or roles (use grants instead)

-- WHY DO TAGS MATTER?
--   1. GOVERNANCE: Identify which columns have PII/PHI
--   2. MASKING: Tag-based masking policies follow the tag
--   3. LINEAGE: Tags propagate through views and lineage
--   4. COST: Tag warehouses by department for chargeback
--   5. DISCOVERY: Find all columns of a certain type
--   6. COMPLIANCE: Map tags to regulatory categories (HIPAA, etc.)

-- ============================================================
-- PART B: Create tags
-- ============================================================

USE SCHEMA BUH_HOL.GOVERNANCE;

-- Tag for PII classification
CREATE OR REPLACE TAG PII_TYPE
  ALLOWED_VALUES = 'SSN', 'NAME', 'EMAIL', 'PHONE', 'ADDRESS', 'DOB', 'MRN'
  COMMENT = 'Identifies the type of personally identifiable information in a column.';

-- Tag for data sensitivity level
CREATE OR REPLACE TAG SENSITIVITY
  ALLOWED_VALUES = 'PUBLIC', 'INTERNAL', 'CONFIDENTIAL', 'RESTRICTED'
  COMMENT = 'Data sensitivity classification level.';

-- Tag for data domain
CREATE OR REPLACE TAG DATA_DOMAIN
  ALLOWED_VALUES = 'CLINICAL', 'FINANCIAL', 'OPERATIONAL', 'RESEARCH'
  COMMENT = 'Business domain that owns this data.';

-- Tag for cost center (on warehouses)
CREATE OR REPLACE TAG COST_CENTER
  COMMENT = 'Department or team responsible for warehouse costs.';

-- ============================================================
-- PART C: Apply tags to objects
-- ============================================================

-- Tag the database
ALTER DATABASE BUH_HOL SET TAG BUH_HOL.GOVERNANCE.DATA_DOMAIN = 'CLINICAL';

-- Tag the warehouse
ALTER WAREHOUSE COMPUTE_WH SET TAG BUH_HOL.GOVERNANCE.COST_CENTER = 'Analytics';

-- Tag sensitive columns in PATIENT_DIM
ALTER TABLE BUH_HOL.RAW.PATIENT_DIM MODIFY COLUMN SSN
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'SSN';
ALTER TABLE BUH_HOL.RAW.PATIENT_DIM MODIFY COLUMN SSN
  SET TAG BUH_HOL.GOVERNANCE.SENSITIVITY = 'RESTRICTED';

ALTER TABLE BUH_HOL.RAW.PATIENT_DIM MODIFY COLUMN PAT_FIRST_NAME
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'NAME';
ALTER TABLE BUH_HOL.RAW.PATIENT_DIM MODIFY COLUMN PAT_LAST_NAME
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'NAME';

ALTER TABLE BUH_HOL.RAW.PATIENT_DIM MODIFY COLUMN EMAIL
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'EMAIL';
ALTER TABLE BUH_HOL.RAW.PATIENT_DIM MODIFY COLUMN PHONE
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'PHONE';
ALTER TABLE BUH_HOL.RAW.PATIENT_DIM MODIFY COLUMN ADDRESS_LINE_1
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'ADDRESS';
ALTER TABLE BUH_HOL.RAW.PATIENT_DIM MODIFY COLUMN BIRTH_DATE
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'DOB';
ALTER TABLE BUH_HOL.RAW.PATIENT_DIM MODIFY COLUMN PAT_MRN
  SET TAG BUH_HOL.GOVERNANCE.PII_TYPE = 'MRN';

-- Tag the whole patient table as confidential
ALTER TABLE BUH_HOL.RAW.PATIENT_DIM
  SET TAG BUH_HOL.GOVERNANCE.SENSITIVITY = 'CONFIDENTIAL';

-- ============================================================
-- PART D: Query tags - find all PII columns
-- ============================================================

-- Find all columns tagged as PII across the database
SELECT
    OBJECT_DATABASE,
    OBJECT_SCHEMA,
    OBJECT_NAME AS TABLE_NAME,
    COLUMN_NAME,
    TAG_VALUE AS PII_TYPE
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE TAG_NAME = 'PII_TYPE'
  AND DOMAIN = 'COLUMN'
  AND OBJECT_DATABASE = 'BUH_HOL'
ORDER BY OBJECT_SCHEMA, TABLE_NAME, COLUMN_NAME;

-- Find all RESTRICTED sensitivity data
SELECT
    OBJECT_DATABASE,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    COLUMN_NAME,
    TAG_VALUE AS SENSITIVITY_LEVEL
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE TAG_NAME = 'SENSITIVITY'
  AND TAG_VALUE = 'RESTRICTED'
  AND OBJECT_DATABASE = 'BUH_HOL'
ORDER BY OBJECT_NAME;

-- ============================================================
-- PART E: Tag-based masking policies
-- ============================================================

-- This is the key pattern: instead of applying masking policies
-- column by column, you attach a masking policy to a TAG.
-- Then every column with that tag is automatically protected.

-- Create masking policies
CREATE OR REPLACE MASKING POLICY BUH_HOL.GOVERNANCE.MASK_SSN
  AS (val VARCHAR) RETURNS VARCHAR ->
  CASE
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_CLINICIAN') THEN '***-**-' || RIGHT(val, 4)
    ELSE '***-**-****'
  END
  COMMENT = 'SSN mask: full for ADMIN, last-4 for CLINICIAN, hidden for others.';

CREATE OR REPLACE MASKING POLICY BUH_HOL.GOVERNANCE.MASK_PII_STRING
  AS (val VARCHAR) RETURNS VARCHAR ->
  CASE
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_CLINICIAN') THEN val
    ELSE '***MASKED***'
  END
  COMMENT = 'PII string mask: visible to ADMIN/CLINICIAN, hidden for others.';

CREATE OR REPLACE MASKING POLICY BUH_HOL.GOVERNANCE.MASK_DOB
  AS (val DATE) RETURNS DATE ->
  CASE
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_ADMIN') THEN val
    WHEN IS_ROLE_IN_SESSION('BUH_LAB_CLINICIAN') THEN val
    ELSE NULL
  END
  COMMENT = 'DOB mask: visible to ADMIN/CLINICIAN, NULL for others.';

-- Attach masking policies to tags (not to individual columns!)
ALTER TAG BUH_HOL.GOVERNANCE.PII_TYPE SET
  MASKING POLICY BUH_HOL.GOVERNANCE.MASK_PII_STRING;

-- Note: tag-based masking applies ONE policy per tag.
-- If you need different policies for SSN vs NAME vs EMAIL,
-- you would use separate tags (PII_SSN, PII_NAME, etc.)
-- or use a conditional policy that checks the tag value.

-- For this lab, the single PII_STRING_MASK covers NAME, EMAIL,
-- PHONE, ADDRESS, and MRN. SSN gets its own direct policy.

-- Apply SSN mask directly (since it needs different behavior)
ALTER TABLE BUH_HOL.RAW.PATIENT_DIM MODIFY COLUMN SSN
  SET MASKING POLICY BUH_HOL.GOVERNANCE.MASK_SSN;

-- Apply DOB mask directly
ALTER TABLE BUH_HOL.RAW.PATIENT_DIM MODIFY COLUMN BIRTH_DATE
  SET MASKING POLICY BUH_HOL.GOVERNANCE.MASK_DOB;

-- ============================================================
-- PART F: Test masking across roles
-- ============================================================

-- ADMIN sees everything
EXECUTE USING POLICY_CONTEXT(
    CURRENT_ROLE => 'BUH_LAB_ADMIN'
)
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, EMAIL, BIRTH_DATE
FROM BUH_HOL.RAW.PATIENT_DIM LIMIT 3;

-- CLINICIAN sees names/email, SSN last-4, DOB visible
EXECUTE USING POLICY_CONTEXT(
    CURRENT_ROLE => 'BUH_LAB_CLINICIAN'
)
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, EMAIL, BIRTH_DATE
FROM BUH_HOL.RAW.PATIENT_DIM LIMIT 3;

-- ANALYST sees masked names, masked SSN, NULL DOB
EXECUTE USING POLICY_CONTEXT(
    CURRENT_ROLE => 'BUH_LAB_ANALYST'
)
SELECT PAT_FIRST_NAME, PAT_LAST_NAME, SSN, EMAIL, BIRTH_DATE
FROM BUH_HOL.RAW.PATIENT_DIM LIMIT 3;

-- ============================================================
-- PART G: Automatic classification (discussion)
-- ============================================================

-- Snowflake can AUTOMATICALLY detect PII using SYSTEM$CLASSIFY.
-- This scans column names, data patterns, and metadata to
-- identify sensitive data and recommend tags.

-- Manual classification (safe to run, read-only):
-- CALL SYSTEM$CLASSIFY('BUH_HOL.RAW.PATIENT_DIM', {'auto_tag': false});

-- Automatic classification profile (production setup):
-- CREATE DATA PRIVACY CLASSIFICATION PROFILE auto_classifier
--   IN DATABASE BUH_HOL
--   CONFIG = (
--     auto_tag = true,
--     maximum_classification_validity_days = 30
--   );
-- ALTER DATABASE BUH_HOL SET CLASSIFICATION_PROFILE = 'auto_classifier';

-- This would automatically scan new and changed tables,
-- apply system tags (SEMANTIC_CATEGORY, PRIVACY_CATEGORY),
-- and optionally trigger masking policies.

-- ============================================================
-- PART H: Tags and Purview - the full picture
-- ============================================================

-- Snowflake tags and Microsoft Purview sensitivity labels are
-- SEPARATE systems that serve similar goals:
--
-- SNOWFLAKE TAGS:
--   - Applied inside Snowflake
--   - Drive masking policies, access controls
--   - Queryable via TAG_REFERENCES
--   - Travel with data through Snowflake lineage
--
-- PURVIEW LABELS:
--   - Applied inside Microsoft ecosystem
--   - Drive DLP, encryption, access in M365/Fabric
--   - Queryable via Purview Data Map
--   - Travel with data through Fabric/M365
--
-- OVERLAP:
--   - Purview can scan Snowflake and discover tables/columns
--   - Purview can apply its own classifications to scanned assets
--   - But Purview labels do NOT auto-sync with Snowflake tags
--   - You would need to align them manually or via automation
--
-- RECOMMENDATION:
--   - Use Snowflake tags to govern data INSIDE Snowflake
--   - Use Purview labels to govern data INSIDE Microsoft
--   - For Iceberg tables in OneLake: both systems can see the data
--   - Maintain a mapping document between tag values and labels

-- ============================================================
-- PART I: Audit - what tags exist in my account?
-- ============================================================

-- Show all tags
SHOW TAGS IN DATABASE BUH_HOL;

-- Show all masking policies
SHOW MASKING POLICIES IN DATABASE BUH_HOL;

-- See what is tagged
SELECT
    TAG_NAME,
    TAG_VALUE,
    OBJECT_DATABASE,
    OBJECT_SCHEMA,
    OBJECT_NAME,
    COLUMN_NAME,
    DOMAIN
FROM SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
WHERE OBJECT_DATABASE = 'BUH_HOL'
ORDER BY TAG_NAME, OBJECT_NAME, COLUMN_NAME;

-- ============================================================
-- CHECKPOINT
-- ============================================================

-- You should understand:
--   1. Tags can be applied to warehouses, databases, schemas,
--      tables, and columns (not rows, not users)
--   2. Tag-based masking applies a policy to ALL columns with
--      that tag - no need to attach policy column by column
--   3. SYSTEM$CLASSIFY can auto-detect PII and recommend tags
--   4. Snowflake tags and Purview labels are separate systems
--      that need manual alignment
--   5. Tags are queryable via SNOWFLAKE.ACCOUNT_USAGE.TAG_REFERENCES
