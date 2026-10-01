/*=============================================================================
  Brown University Health - Automation & Governance Hands-On Lab
  Script 00: Setup - Database, Schemas, Roles, Synthetic Data
  
  PREREQUISITES:
    - Role with CREATE DATABASE, CREATE WAREHOUSE, CREATE ROLE privileges
      (ACCOUNTADMIN on a trial account works)
    - Edit the warehouse name below if yours is not COMPUTE_WH
  
  WHAT THIS CREATES:
    - Database:    BUH_AUTOMATION_LAB
    - Schemas:     RAW, CURATED, GOVERNANCE, VENDOR_LANDING, LOGS
    - Roles:       BUH_LAB_ADMIN, BUH_LAB_ANALYST, BUH_LAB_CLINICIAN
    - Tables:      Synthetic Clarity-like clinical tables, vendor files,
                   config tables, and multimodal metadata samples
  
  SAFE TO RERUN: Yes - uses CREATE OR REPLACE throughout
=============================================================================*/

-- ============================================================
-- 0. ENVIRONMENT
-- ============================================================
USE ROLE ACCOUNTADMIN;
CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================
-- 1. DATABASE AND SCHEMAS
-- ============================================================
CREATE OR REPLACE DATABASE BUH_AUTOMATION_LAB;

CREATE SCHEMA BUH_AUTOMATION_LAB.RAW;
CREATE SCHEMA BUH_AUTOMATION_LAB.CURATED;
CREATE SCHEMA BUH_AUTOMATION_LAB.GOVERNANCE;
CREATE SCHEMA BUH_AUTOMATION_LAB.VENDOR_LANDING;
CREATE SCHEMA BUH_AUTOMATION_LAB.LOGS;

-- ============================================================
-- 2. LAB ROLES
-- ============================================================
CREATE ROLE IF NOT EXISTS BUH_LAB_ADMIN;
CREATE ROLE IF NOT EXISTS BUH_LAB_ANALYST;
CREATE ROLE IF NOT EXISTS BUH_LAB_CLINICIAN;

GRANT ROLE BUH_LAB_ADMIN TO ROLE ACCOUNTADMIN;
GRANT ROLE BUH_LAB_ANALYST TO ROLE BUH_LAB_ADMIN;
GRANT ROLE BUH_LAB_CLINICIAN TO ROLE BUH_LAB_ADMIN;

GRANT USAGE ON DATABASE BUH_AUTOMATION_LAB TO ROLE BUH_LAB_ADMIN;
GRANT USAGE ON DATABASE BUH_AUTOMATION_LAB TO ROLE BUH_LAB_ANALYST;
GRANT USAGE ON DATABASE BUH_AUTOMATION_LAB TO ROLE BUH_LAB_CLINICIAN;

GRANT ALL ON ALL SCHEMAS IN DATABASE BUH_AUTOMATION_LAB TO ROLE BUH_LAB_ADMIN;
GRANT USAGE ON ALL SCHEMAS IN DATABASE BUH_AUTOMATION_LAB TO ROLE BUH_LAB_ANALYST;
GRANT USAGE ON ALL SCHEMAS IN DATABASE BUH_AUTOMATION_LAB TO ROLE BUH_LAB_CLINICIAN;

GRANT SELECT ON ALL TABLES IN DATABASE BUH_AUTOMATION_LAB TO ROLE BUH_LAB_ANALYST;
GRANT SELECT ON ALL TABLES IN DATABASE BUH_AUTOMATION_LAB TO ROLE BUH_LAB_CLINICIAN;

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE BUH_LAB_ADMIN;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE BUH_LAB_ANALYST;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE BUH_LAB_CLINICIAN;

-- Future grants so new tables are automatically accessible
GRANT SELECT ON FUTURE TABLES IN DATABASE BUH_AUTOMATION_LAB TO ROLE BUH_LAB_ANALYST;
GRANT SELECT ON FUTURE TABLES IN DATABASE BUH_AUTOMATION_LAB TO ROLE BUH_LAB_CLINICIAN;

-- ============================================================
-- 3. SYNTHETIC CLARITY-LIKE SOURCE TABLES (RAW schema)
--    These represent what an Epic Clarity extract looks like
--    after a bulk load. All data is fabricated.
-- ============================================================
USE SCHEMA BUH_AUTOMATION_LAB.RAW;

-- 3a. PATIENT_DIM - core patient demographics
CREATE OR REPLACE TABLE PATIENT_DIM (
    PAT_ID          VARCHAR(20)   NOT NULL,
    PAT_MRN         VARCHAR(15)   NOT NULL,
    PAT_FIRST_NAME  VARCHAR(50),
    PAT_LAST_NAME   VARCHAR(50),
    BIRTH_DATE      DATE,
    SSN             VARCHAR(11),
    ADDRESS_LINE_1  VARCHAR(100),
    CITY            VARCHAR(50),
    STATE           VARCHAR(2),
    ZIP_CODE        VARCHAR(10),
    PHONE           VARCHAR(15),
    EMAIL           VARCHAR(100),
    PRIM_LANGUAGE   VARCHAR(30),
    RACE            VARCHAR(30),
    ETHNICITY       VARCHAR(30),
    GENDER          VARCHAR(10),
    LOAD_TS         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO PATIENT_DIM (PAT_ID, PAT_MRN, PAT_FIRST_NAME, PAT_LAST_NAME, BIRTH_DATE, SSN, ADDRESS_LINE_1, CITY, STATE, ZIP_CODE, PHONE, EMAIL, PRIM_LANGUAGE, RACE, ETHNICITY, GENDER)
VALUES
('P100001','MRN-900001','Maria','Santos','1965-03-14','111-22-3333','100 Hope St','Providence','RI','02906','401-555-0101','msantos@example.com','English','White','Non-Hispanic','Female'),
('P100002','MRN-900002','James','Okafor','1978-11-02','222-33-4444','45 Thayer St','Providence','RI','02912','401-555-0102','jokafor@example.com','English','Black','Non-Hispanic','Male'),
('P100003','MRN-900003','Lin','Chen','1990-07-21','333-44-5555','200 Wickenden St','Providence','RI','02903','401-555-0103','lchen@example.com','Mandarin','Asian','Non-Hispanic','Female'),
('P100004','MRN-900004','Robert','Williams','1955-01-30','444-55-6666','88 Broad St','Providence','RI','02903','401-555-0104','rwilliams@example.com','English','White','Non-Hispanic','Male'),
('P100005','MRN-900005','Fatima','Al-Hassan','1988-09-15','555-66-7777','12 Benefit St','Providence','RI','02904','401-555-0105','falhassan@example.com','Arabic','White','Hispanic','Female'),
('P100006','MRN-900006','David','Park','1972-04-08','666-77-8888','300 Brook St','Providence','RI','02906','401-555-0106','dpark@example.com','English','Asian','Non-Hispanic','Male'),
('P100007','MRN-900007','Sarah','Johnson','1983-12-25','777-88-9999','55 Power St','Providence','RI','02906','401-555-0107','sjohnson@example.com','English','White','Non-Hispanic','Female'),
('P100008','MRN-900008','Carlos','Rivera','1995-06-10','888-99-0000','400 Hope St','Providence','RI','02906','401-555-0108','crivera@example.com','Spanish','White','Hispanic','Male');

-- 3b. ENCOUNTER_FACT - simplified encounter records
CREATE OR REPLACE TABLE ENCOUNTER_FACT (
    ENCOUNTER_ID       VARCHAR(20) NOT NULL,
    PAT_ID             VARCHAR(20) NOT NULL,
    ENCOUNTER_TYPE     VARCHAR(30),
    ADMIT_DATE         DATE,
    DISCHARGE_DATE     DATE,
    DEPARTMENT         VARCHAR(50),
    ATTENDING_PROV_ID  VARCHAR(20),
    PRIMARY_DX_CODE    VARCHAR(10),
    PRIMARY_DX_NAME    VARCHAR(200),
    ENCOUNTER_STATUS   VARCHAR(20),
    LOAD_TS            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO ENCOUNTER_FACT (ENCOUNTER_ID, PAT_ID, ENCOUNTER_TYPE, ADMIT_DATE, DISCHARGE_DATE, DEPARTMENT, ATTENDING_PROV_ID, PRIMARY_DX_CODE, PRIMARY_DX_NAME, ENCOUNTER_STATUS)
VALUES
('E200001','P100001','Inpatient','2024-08-10','2024-08-14','Cardiology','PROV-001','I21.0','Acute ST-elevation MI','Discharged'),
('E200002','P100002','Outpatient','2024-09-01',NULL,'Primary Care','PROV-002','E11.9','Type 2 diabetes mellitus','Completed'),
('E200003','P100003','Emergency','2024-09-15','2024-09-15','Emergency Dept','PROV-003','S52.501A','Fracture of lower end of radius','Discharged'),
('E200004','P100004','Inpatient','2024-09-20','2024-09-28','Oncology','PROV-004','C34.90','Malignant neoplasm of lung','Discharged'),
('E200005','P100001','Outpatient','2024-10-01',NULL,'Cardiology','PROV-001','I21.0','Acute ST-elevation MI follow-up','Completed'),
('E200006','P100005','Outpatient','2024-10-05',NULL,'OB/GYN','PROV-005','Z34.00','Supervision of normal pregnancy','Completed'),
('E200007','P100006','Inpatient','2024-10-10','2024-10-12','Orthopedics','PROV-006','M17.11','Primary osteoarthritis, right knee','Discharged'),
('E200008','P100007','Emergency','2024-10-12','2024-10-12','Emergency Dept','PROV-003','J06.9','Acute upper respiratory infection','Discharged'),
('E200009','P100008','Outpatient','2024-10-15',NULL,'Behavioral Health','PROV-007','F32.1','Major depressive disorder, moderate','Completed'),
('E200010','P100002','Inpatient','2024-10-18','2024-10-22','Nephrology','PROV-008','N18.4','Chronic kidney disease, stage 4','Discharged');

-- 3c. ORDERS - simplified order records (labs, meds, imaging)
CREATE OR REPLACE TABLE ORDERS (
    ORDER_ID          VARCHAR(20) NOT NULL,
    ENCOUNTER_ID      VARCHAR(20) NOT NULL,
    PAT_ID            VARCHAR(20) NOT NULL,
    ORDER_TYPE        VARCHAR(20),
    ORDER_NAME        VARCHAR(200),
    ORDER_STATUS      VARCHAR(20),
    ORDERING_PROV_ID  VARCHAR(20),
    ORDER_DATE        DATE,
    RESULT_VALUE      VARCHAR(50),
    RESULT_UNIT       VARCHAR(20),
    ABNORMAL_FLAG     VARCHAR(5),
    LOAD_TS           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO ORDERS (ORDER_ID, ENCOUNTER_ID, PAT_ID, ORDER_TYPE, ORDER_NAME, ORDER_STATUS, ORDERING_PROV_ID, ORDER_DATE, RESULT_VALUE, RESULT_UNIT, ABNORMAL_FLAG)
VALUES
('O300001','E200001','P100001','Lab','Troponin I','Completed','PROV-001','2024-08-10','2.45','ng/mL','H'),
('O300002','E200001','P100001','Lab','BNP','Completed','PROV-001','2024-08-10','890','pg/mL','H'),
('O300003','E200001','P100001','Imaging','Cardiac Catheterization','Completed','PROV-001','2024-08-11',NULL,NULL,NULL),
('O300004','E200002','P100002','Lab','HbA1c','Completed','PROV-002','2024-09-01','8.2','%','H'),
('O300005','E200002','P100002','Med','Metformin 500mg','Active','PROV-002','2024-09-01',NULL,NULL,NULL),
('O300006','E200003','P100003','Imaging','X-Ray Wrist','Completed','PROV-003','2024-09-15',NULL,NULL,NULL),
('O300007','E200004','P100004','Lab','CBC with Diff','Completed','PROV-004','2024-09-20','3.1','K/uL','L'),
('O300008','E200004','P100004','Imaging','CT Chest with Contrast','Completed','PROV-004','2024-09-21',NULL,NULL,NULL),
('O300009','E200010','P100002','Lab','Creatinine','Completed','PROV-008','2024-10-18','4.2','mg/dL','H'),
('O300010','E200010','P100002','Lab','GFR','Completed','PROV-008','2024-10-18','22','mL/min','L');

-- ============================================================
-- 4. IMPORT CONFIGURATION TABLE (CURATED schema)
--    This is the "config-driven" approach to Clarity imports.
--    Each row defines one source table to import.
-- ============================================================
USE SCHEMA BUH_AUTOMATION_LAB.CURATED;

CREATE OR REPLACE TABLE IMPORT_CONFIG (
    CONFIG_ID        NUMBER AUTOINCREMENT,
    SOURCE_SCHEMA    VARCHAR(100) DEFAULT 'RAW',
    SOURCE_TABLE     VARCHAR(100) NOT NULL,
    TARGET_SCHEMA    VARCHAR(100) DEFAULT 'CURATED',
    TARGET_TABLE     VARCHAR(100) NOT NULL,
    KEY_COLUMNS      VARCHAR(500) NOT NULL,
    ENABLED          BOOLEAN DEFAULT TRUE,
    LAST_RUN_TS      TIMESTAMP_NTZ,
    LAST_RUN_STATUS  VARCHAR(20),
    NOTES            VARCHAR(500)
);

INSERT INTO IMPORT_CONFIG (SOURCE_TABLE, TARGET_TABLE, KEY_COLUMNS, NOTES)
VALUES
('PATIENT_DIM',    'DIM_PATIENT',    'PAT_ID',       'Core patient demographics from Clarity'),
('ENCOUNTER_FACT', 'FACT_ENCOUNTER', 'ENCOUNTER_ID',  'Encounter records from Clarity'),
('ORDERS',         'FACT_ORDERS',    'ORDER_ID',      'Lab, med, and imaging orders from Clarity');

-- ============================================================
-- 5. VENDOR FILE LANDING AREA (VENDOR_LANDING schema)
--    Simulates external vendor files with good, drifted,
--    and invalid payloads.
-- ============================================================
USE SCHEMA BUH_AUTOMATION_LAB.VENDOR_LANDING;

-- 5a. Expected schema for vendor lab results
CREATE OR REPLACE TABLE VENDOR_LAB_EXPECTED_SCHEMA (
    COL_NAME     VARCHAR(100),
    COL_TYPE     VARCHAR(50),
    IS_REQUIRED  BOOLEAN,
    VALID_REGEX  VARCHAR(200)
);

INSERT INTO VENDOR_LAB_EXPECTED_SCHEMA VALUES
('VENDOR_ID',    'VARCHAR', TRUE,  '^VL-[0-9]{6}$'),
('PAT_MRN',      'VARCHAR', TRUE,  '^MRN-[0-9]{6}$'),
('TEST_CODE',    'VARCHAR', TRUE,  NULL),
('TEST_NAME',    'VARCHAR', TRUE,  NULL),
('RESULT_VALUE', 'VARCHAR', FALSE, NULL),
('RESULT_UNIT',  'VARCHAR', FALSE, NULL),
('RESULT_DATE',  'DATE',    TRUE,  NULL),
('ABNORMAL_YN',  'VARCHAR', FALSE, '^[YN]$');

-- 5b. GOOD vendor payload - matches expected schema
CREATE OR REPLACE TABLE VENDOR_LAB_BATCH_GOOD (
    VENDOR_ID    VARCHAR(20),
    PAT_MRN      VARCHAR(15),
    TEST_CODE    VARCHAR(20),
    TEST_NAME    VARCHAR(200),
    RESULT_VALUE VARCHAR(50),
    RESULT_UNIT  VARCHAR(20),
    RESULT_DATE  DATE,
    ABNORMAL_YN  VARCHAR(1)
);

INSERT INTO VENDOR_LAB_BATCH_GOOD VALUES
('VL-000001','MRN-900001','GLU','Glucose','95','mg/dL','2024-10-20','N'),
('VL-000002','MRN-900002','GLU','Glucose','142','mg/dL','2024-10-20','Y'),
('VL-000003','MRN-900003','CBC','Complete Blood Count','normal',NULL,'2024-10-20','N'),
('VL-000004','MRN-900004','PSA','Prostate Specific Antigen','1.2','ng/mL','2024-10-21','N'),
('VL-000005','MRN-900001','LIPID','Lipid Panel','LDL 130','mg/dL','2024-10-21','Y');

-- 5c. DRIFTED vendor payload - has extra columns
CREATE OR REPLACE TABLE VENDOR_LAB_BATCH_DRIFTED (
    VENDOR_ID    VARCHAR(20),
    PAT_MRN      VARCHAR(15),
    TEST_CODE    VARCHAR(20),
    TEST_NAME    VARCHAR(200),
    RESULT_VALUE VARCHAR(50),
    RESULT_UNIT  VARCHAR(20),
    RESULT_DATE  DATE,
    ABNORMAL_YN  VARCHAR(1),
    NEW_COL_METHODOLOGY VARCHAR(50),
    NEW_COL_LAB_SITE    VARCHAR(50)
);

INSERT INTO VENDOR_LAB_BATCH_DRIFTED VALUES
('VL-000006','MRN-900005','HCG','HCG Quantitative','15200','mIU/mL','2024-10-22','N','ECLIA','Quest East'),
('VL-000007','MRN-900006','ESR','Sed Rate','42','mm/hr','2024-10-22','Y','Westergren','LabCorp RI');

-- 5d. INVALID vendor payload - missing required fields, bad formats
CREATE OR REPLACE TABLE VENDOR_LAB_BATCH_INVALID (
    VENDOR_ID    VARCHAR(20),
    PAT_MRN      VARCHAR(15),
    TEST_CODE    VARCHAR(20),
    TEST_NAME    VARCHAR(200),
    RESULT_VALUE VARCHAR(50),
    RESULT_UNIT  VARCHAR(20),
    RESULT_DATE  DATE,
    ABNORMAL_YN  VARCHAR(1)
);

INSERT INTO VENDOR_LAB_BATCH_INVALID VALUES
('BADID','MRN-900007','CBC','Complete Blood Count','normal',NULL,'2024-10-23','N'),
(NULL,'MRN-900008','BMP','Basic Metabolic Panel','normal',NULL,'2024-10-23','N'),
('VL-000010',NULL,'TSH','Thyroid Stimulating Hormone','2.1','uIU/mL','2024-10-23','N'),
('VL-000011','MRN-900001','LIPID','Lipid Panel','see note',NULL,NULL,'X');

-- 5e. Accepted and Quarantine targets
CREATE OR REPLACE TABLE VENDOR_LAB_ACCEPTED (
    VENDOR_ID    VARCHAR(20),
    PAT_MRN      VARCHAR(15),
    TEST_CODE    VARCHAR(20),
    TEST_NAME    VARCHAR(200),
    RESULT_VALUE VARCHAR(50),
    RESULT_UNIT  VARCHAR(20),
    RESULT_DATE  DATE,
    ABNORMAL_YN  VARCHAR(1),
    BATCH_ID     VARCHAR(50),
    ACCEPTED_TS  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE VENDOR_LAB_QUARANTINE (
    VENDOR_ID    VARCHAR(20),
    PAT_MRN      VARCHAR(15),
    TEST_CODE    VARCHAR(20),
    TEST_NAME    VARCHAR(200),
    RESULT_VALUE VARCHAR(50),
    RESULT_UNIT  VARCHAR(20),
    RESULT_DATE  DATE,
    ABNORMAL_YN  VARCHAR(1),
    BATCH_ID     VARCHAR(50),
    REJECTION_REASONS VARIANT,
    QUARANTINED_TS TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- 6. LOGGING TABLE (LOGS schema)
-- ============================================================
USE SCHEMA BUH_AUTOMATION_LAB.LOGS;

CREATE OR REPLACE TABLE RUN_LOG (
    LOG_ID       NUMBER AUTOINCREMENT,
    RUN_ID       VARCHAR(50)   NOT NULL,
    STEP_NAME    VARCHAR(100),
    LOG_LEVEL    VARCHAR(10)   NOT NULL,  -- INFO, WARN, ERROR
    MESSAGE      VARCHAR(4000),
    DETAIL       VARIANT,
    LOGGED_AT    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- 7. MULTIMODAL / AI SAMPLE DATA (RAW schema)
-- ============================================================
USE SCHEMA BUH_AUTOMATION_LAB.RAW;

-- 7a. Clinical notes for AI annotation
CREATE OR REPLACE TABLE CLINICAL_NOTES (
    NOTE_ID      VARCHAR(20),
    PAT_ID       VARCHAR(20),
    ENCOUNTER_ID VARCHAR(20),
    NOTE_TYPE    VARCHAR(30),
    NOTE_TEXT    VARCHAR(8000),
    AUTHOR_ID    VARCHAR(20),
    NOTE_DATE    DATE
);

INSERT INTO CLINICAL_NOTES VALUES
('N400001','P100001','E200001','Discharge Summary',
 'Patient is a 59-year-old female admitted with acute ST-elevation myocardial infarction. Troponin peaked at 2.45. Underwent cardiac catheterization on hospital day 2 with drug-eluting stent placement to the LAD. Post-procedure course uncomplicated. Discharged on aspirin, clopidogrel, atorvastatin, metoprolol, and lisinopril. Follow-up in cardiology clinic in 2 weeks. Patient educated on cardiac rehab referral.',
 'PROV-001','2024-08-14'),
('N400002','P100004','E200004','Progress Note',
 'Patient is a 69-year-old male with newly diagnosed non-small cell lung cancer, stage IIIA. CT chest shows 4.2cm RUL mass with mediastinal lymphadenopathy. PET scan pending. Discussed treatment options including concurrent chemoradiation vs surgical resection. Patient prefers to await PET results before deciding. Pain well controlled on current regimen. Continue supportive care.',
 'PROV-004','2024-09-22'),
('N400003','P100008','E200009','Behavioral Health Assessment',
 'Patient is a 29-year-old male presenting with worsening depressive symptoms over 3 months. PHQ-9 score of 16 (moderately severe). Reports difficulty sleeping, decreased appetite, anhedonia, and difficulty concentrating at work. Denies SI/HI. No prior psychiatric history. Started on sertraline 50mg daily. Therapy referral placed. Follow-up in 4 weeks.',
 'PROV-007','2024-10-15');

-- 7b. Image metadata catalog (not actual images)
CREATE OR REPLACE TABLE IMAGE_METADATA (
    IMAGE_ID       VARCHAR(20),
    PAT_ID         VARCHAR(20),
    ENCOUNTER_ID   VARCHAR(20),
    MODALITY       VARCHAR(30),
    BODY_PART      VARCHAR(50),
    IMAGE_DATE     DATE,
    DICOM_STUDY_UID VARCHAR(100),
    FILE_PATH      VARCHAR(500),
    AI_DESCRIPTION VARCHAR(2000)
);

INSERT INTO IMAGE_METADATA (IMAGE_ID, PAT_ID, ENCOUNTER_ID, MODALITY, BODY_PART, IMAGE_DATE, DICOM_STUDY_UID, FILE_PATH, AI_DESCRIPTION)
VALUES
('IMG-001','P100001','E200001','Angiography','Heart','2024-08-11','1.2.840.113619.2.001','s3://imaging-archive/P100001/angio_20240811.dcm',NULL),
('IMG-002','P100003','E200003','X-Ray','Wrist-Left','2024-09-15','1.2.840.113619.2.002','s3://imaging-archive/P100003/xray_wrist_20240915.dcm',NULL),
('IMG-003','P100004','E200004','CT','Chest','2024-09-21','1.2.840.113619.2.003','s3://imaging-archive/P100004/ct_chest_20240921.dcm',NULL);

-- 7c. Simplified omics metadata
CREATE OR REPLACE TABLE OMICS_METADATA (
    SAMPLE_ID    VARCHAR(20),
    PAT_ID       VARCHAR(20),
    ASSAY_TYPE   VARCHAR(30),
    PANEL_NAME   VARCHAR(100),
    GENE_COUNT   NUMBER,
    VARIANTS_DETECTED NUMBER,
    COLLECTION_DATE DATE,
    LAB_NAME     VARCHAR(100),
    STATUS       VARCHAR(20),
    REPORT_URL   VARCHAR(500)
);

INSERT INTO OMICS_METADATA VALUES
('OMX-001','P100004','WES','Comprehensive Genomic Panel',523,12,'2024-09-25','Foundation Medicine','Complete','s3://omics-reports/P100004/fmi_report.pdf'),
('OMX-002','P100001','Targeted Panel','Cardio Gene Panel',84,3,'2024-08-12','Invitae','Complete','s3://omics-reports/P100001/invitae_cardio.pdf');

-- ============================================================
-- 8. CHECKPOINT: Verify setup
-- ============================================================
SELECT 'PATIENT_DIM' AS TABLE_NAME, COUNT(*) AS ROW_COUNT FROM BUH_AUTOMATION_LAB.RAW.PATIENT_DIM
UNION ALL
SELECT 'ENCOUNTER_FACT', COUNT(*) FROM BUH_AUTOMATION_LAB.RAW.ENCOUNTER_FACT
UNION ALL
SELECT 'ORDERS', COUNT(*) FROM BUH_AUTOMATION_LAB.RAW.ORDERS
UNION ALL
SELECT 'CLINICAL_NOTES', COUNT(*) FROM BUH_AUTOMATION_LAB.RAW.CLINICAL_NOTES
UNION ALL
SELECT 'IMAGE_METADATA', COUNT(*) FROM BUH_AUTOMATION_LAB.RAW.IMAGE_METADATA
UNION ALL
SELECT 'OMICS_METADATA', COUNT(*) FROM BUH_AUTOMATION_LAB.RAW.OMICS_METADATA
UNION ALL
SELECT 'IMPORT_CONFIG', COUNT(*) FROM BUH_AUTOMATION_LAB.CURATED.IMPORT_CONFIG
UNION ALL
SELECT 'VENDOR_LAB_BATCH_GOOD', COUNT(*) FROM BUH_AUTOMATION_LAB.VENDOR_LANDING.VENDOR_LAB_BATCH_GOOD
UNION ALL
SELECT 'VENDOR_LAB_BATCH_DRIFTED', COUNT(*) FROM BUH_AUTOMATION_LAB.VENDOR_LANDING.VENDOR_LAB_BATCH_DRIFTED
UNION ALL
SELECT 'VENDOR_LAB_BATCH_INVALID', COUNT(*) FROM BUH_AUTOMATION_LAB.VENDOR_LANDING.VENDOR_LAB_BATCH_INVALID
ORDER BY TABLE_NAME;

/*
  EXPECTED OUTPUT:
  CLINICAL_NOTES              3
  ENCOUNTER_FACT             10
  IMAGE_METADATA              3
  IMPORT_CONFIG               3
  OMICS_METADATA              2
  ORDERS                     10
  PATIENT_DIM                 8
  VENDOR_LAB_BATCH_DRIFTED    2
  VENDOR_LAB_BATCH_GOOD       5
  VENDOR_LAB_BATCH_INVALID    4
*/
