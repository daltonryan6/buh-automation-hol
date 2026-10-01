/*=============================================================================
  Brown University Health - Hands-On Lab
  Script 00: Setup - Database, Schemas, Roles, Synthetic Data
  
  PREREQUISITES:
    - Snowflake trial or existing account with ACCOUNTADMIN
    - No pre-configuration needed - this script creates everything
  
  WHAT THIS CREATES:
    - Database:  BUH_HOL
    - Schemas:   RAW, CURATED, GOLD, GOVERNANCE
    - Roles:     BUH_LAB_ADMIN, BUH_LAB_ANALYST, BUH_LAB_CLINICIAN
    - Tables:    Synthetic Clarity-like clinical tables for dynamic
                 table pipelines, governance, and Iceberg demos
  
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
CREATE OR REPLACE DATABASE BUH_HOL;

CREATE SCHEMA BUH_HOL.RAW;
CREATE SCHEMA BUH_HOL.CURATED;
CREATE SCHEMA BUH_HOL.GOLD;
CREATE SCHEMA BUH_HOL.GOVERNANCE;

-- ============================================================
-- 2. LAB ROLES
-- ============================================================
CREATE ROLE IF NOT EXISTS BUH_LAB_ADMIN;
CREATE ROLE IF NOT EXISTS BUH_LAB_ANALYST;
CREATE ROLE IF NOT EXISTS BUH_LAB_CLINICIAN;

GRANT ROLE BUH_LAB_ADMIN TO ROLE ACCOUNTADMIN;
GRANT ROLE BUH_LAB_ANALYST TO ROLE BUH_LAB_ADMIN;
GRANT ROLE BUH_LAB_CLINICIAN TO ROLE BUH_LAB_ADMIN;

GRANT USAGE ON DATABASE BUH_HOL TO ROLE BUH_LAB_ADMIN;
GRANT USAGE ON DATABASE BUH_HOL TO ROLE BUH_LAB_ANALYST;
GRANT USAGE ON DATABASE BUH_HOL TO ROLE BUH_LAB_CLINICIAN;

GRANT ALL ON ALL SCHEMAS IN DATABASE BUH_HOL TO ROLE BUH_LAB_ADMIN;
GRANT USAGE ON ALL SCHEMAS IN DATABASE BUH_HOL TO ROLE BUH_LAB_ANALYST;
GRANT USAGE ON ALL SCHEMAS IN DATABASE BUH_HOL TO ROLE BUH_LAB_CLINICIAN;

GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE BUH_LAB_ADMIN;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE BUH_LAB_ANALYST;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE BUH_LAB_CLINICIAN;

GRANT SELECT ON FUTURE TABLES IN DATABASE BUH_HOL TO ROLE BUH_LAB_ANALYST;
GRANT SELECT ON FUTURE TABLES IN DATABASE BUH_HOL TO ROLE BUH_LAB_CLINICIAN;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN DATABASE BUH_HOL TO ROLE BUH_LAB_ANALYST;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN DATABASE BUH_HOL TO ROLE BUH_LAB_CLINICIAN;
GRANT SELECT ON FUTURE VIEWS IN DATABASE BUH_HOL TO ROLE BUH_LAB_ANALYST;
GRANT SELECT ON FUTURE VIEWS IN DATABASE BUH_HOL TO ROLE BUH_LAB_CLINICIAN;

-- ============================================================
-- 3. RAW LAYER - Simulated Clarity extracts
--    These represent landing tables after a bulk load from Epic.
--    All data is fabricated.
-- ============================================================
USE SCHEMA BUH_HOL.RAW;

-- 3a. PATIENT_DIM - core patient demographics
CREATE OR REPLACE TABLE PATIENT_DIM (
    PAT_ID          VARCHAR(20) NOT NULL,
    PAT_MRN         VARCHAR(15) NOT NULL,
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
    GENDER          VARCHAR(10),
    LOAD_TS         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO PATIENT_DIM (PAT_ID,PAT_MRN,PAT_FIRST_NAME,PAT_LAST_NAME,BIRTH_DATE,SSN,ADDRESS_LINE_1,CITY,STATE,ZIP_CODE,PHONE,EMAIL,PRIM_LANGUAGE,GENDER) VALUES
('P100001','MRN-900001','Maria','Santos','1965-03-14','111-22-3333','100 Hope St','Providence','RI','02906','401-555-0101','msantos@example.com','English','Female'),
('P100002','MRN-900002','James','Okafor','1978-11-02','222-33-4444','45 Thayer St','Providence','RI','02912','401-555-0102','jokafor@example.com','English','Male'),
('P100003','MRN-900003','Lin','Chen','1990-07-21','333-44-5555','200 Wickenden St','Providence','RI','02903','401-555-0103','lchen@example.com','Mandarin','Female'),
('P100004','MRN-900004','Robert','Williams','1955-01-30','444-55-6666','88 Broad St','Providence','RI','02903','401-555-0104','rwilliams@example.com','English','Male'),
('P100005','MRN-900005','Fatima','Al-Hassan','1988-09-15','555-66-7777','12 Benefit St','Providence','RI','02904','401-555-0105','falhassan@example.com','Arabic','Female'),
('P100006','MRN-900006','David','Park','1972-04-08','666-77-8888','300 Brook St','Providence','RI','02906','401-555-0106','dpark@example.com','English','Male'),
('P100007','MRN-900007','Sarah','Johnson','1983-12-25','777-88-9999','55 Power St','Providence','RI','02906','401-555-0107','sjohnson@example.com','English','Female'),
('P100008','MRN-900008','Carlos','Rivera','1995-06-10','888-99-0000','400 Hope St','Providence','RI','02906','401-555-0108','crivera@example.com','Spanish','Male');

-- 3b. ENCOUNTER_FACT
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
    TOTAL_CHARGES      NUMBER(12,2),
    LOAD_TS            TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO ENCOUNTER_FACT VALUES
('E200001','P100001','Inpatient','2024-08-10','2024-08-14','Cardiology','PROV-001','I21.0','Acute ST-elevation MI','Discharged',45200.00,CURRENT_TIMESTAMP()),
('E200002','P100002','Outpatient','2024-09-01',NULL,'Primary Care','PROV-002','E11.9','Type 2 diabetes mellitus','Completed',350.00,CURRENT_TIMESTAMP()),
('E200003','P100003','Emergency','2024-09-15','2024-09-15','Emergency Dept','PROV-003','S52.501A','Fracture of lower end of radius','Discharged',8900.00,CURRENT_TIMESTAMP()),
('E200004','P100004','Inpatient','2024-09-20','2024-09-28','Oncology','PROV-004','C34.90','Malignant neoplasm of lung','Discharged',72500.00,CURRENT_TIMESTAMP()),
('E200005','P100001','Outpatient','2024-10-01',NULL,'Cardiology','PROV-001','I21.0','Acute ST-elevation MI follow-up','Completed',275.00,CURRENT_TIMESTAMP()),
('E200006','P100005','Outpatient','2024-10-05',NULL,'OB/GYN','PROV-005','Z34.00','Supervision of normal pregnancy','Completed',425.00,CURRENT_TIMESTAMP()),
('E200007','P100006','Inpatient','2024-10-10','2024-10-12','Orthopedics','PROV-006','M17.11','Primary osteoarthritis right knee','Discharged',38900.00,CURRENT_TIMESTAMP()),
('E200008','P100007','Emergency','2024-10-12','2024-10-12','Emergency Dept','PROV-003','J06.9','Acute upper respiratory infection','Discharged',2100.00,CURRENT_TIMESTAMP()),
('E200009','P100008','Outpatient','2024-10-15',NULL,'Behavioral Health','PROV-007','F32.1','Major depressive disorder moderate','Completed',310.00,CURRENT_TIMESTAMP()),
('E200010','P100002','Inpatient','2024-10-18','2024-10-22','Nephrology','PROV-008','N18.4','Chronic kidney disease stage 4','Discharged',28700.00,CURRENT_TIMESTAMP());

-- 3c. LAB_RESULTS
CREATE OR REPLACE TABLE LAB_RESULTS (
    RESULT_ID      VARCHAR(20) NOT NULL,
    ENCOUNTER_ID   VARCHAR(20) NOT NULL,
    PAT_ID         VARCHAR(20) NOT NULL,
    TEST_CODE      VARCHAR(20),
    TEST_NAME      VARCHAR(200),
    RESULT_VALUE   NUMBER(10,2),
    RESULT_UNIT    VARCHAR(20),
    REFERENCE_LOW  NUMBER(10,2),
    REFERENCE_HIGH NUMBER(10,2),
    RESULT_DATE    TIMESTAMP_NTZ,
    LOAD_TS        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO LAB_RESULTS (RESULT_ID,ENCOUNTER_ID,PAT_ID,TEST_CODE,TEST_NAME,RESULT_VALUE,RESULT_UNIT,REFERENCE_LOW,REFERENCE_HIGH,RESULT_DATE) VALUES
('R001','E200001','P100001','TROP','Troponin I',2.45,'ng/mL',0.00,0.04,'2024-08-10 06:30:00'),
('R002','E200001','P100001','BNP','BNP',890.00,'pg/mL',0.00,100.00,'2024-08-10 06:30:00'),
('R003','E200002','P100002','HBA1C','HbA1c',8.20,'%',4.00,5.60,'2024-09-01 09:00:00'),
('R004','E200004','P100004','WBC','WBC',3.10,'K/uL',4.50,11.00,'2024-09-20 07:00:00'),
('R005','E200010','P100002','CREAT','Creatinine',4.20,'mg/dL',0.70,1.30,'2024-10-18 08:00:00'),
('R006','E200010','P100002','GFR','eGFR',22.00,'mL/min',90.00,120.00,'2024-10-18 08:00:00'),
('R007','E200001','P100001','CHOL','Total Cholesterol',245.00,'mg/dL',0.00,200.00,'2024-08-10 06:30:00'),
('R008','E200001','P100001','LDL','LDL Cholesterol',165.00,'mg/dL',0.00,100.00,'2024-08-10 06:30:00'),
('R009','E200005','P100001','TROP','Troponin I',0.02,'ng/mL',0.00,0.04,'2024-10-01 10:00:00'),
('R010','E200005','P100001','BNP','BNP',85.00,'pg/mL',0.00,100.00,'2024-10-01 10:00:00');

-- 3d. PROVIDER_DIM
CREATE OR REPLACE TABLE PROVIDER_DIM (
    PROV_ID        VARCHAR(20) NOT NULL,
    PROV_NAME      VARCHAR(100),
    SPECIALTY      VARCHAR(50),
    DEPARTMENT     VARCHAR(50),
    NPI            VARCHAR(10),
    ACTIVE         BOOLEAN DEFAULT TRUE
);

INSERT INTO PROVIDER_DIM VALUES
('PROV-001','Dr. Amy Chen','Cardiology','Cardiology','1234567890',TRUE),
('PROV-002','Dr. Marcus Brown','Internal Medicine','Primary Care','2345678901',TRUE),
('PROV-003','Dr. Lisa Park','Emergency Medicine','Emergency Dept','3456789012',TRUE),
('PROV-004','Dr. James Wright','Oncology','Oncology','4567890123',TRUE),
('PROV-005','Dr. Sarah Kim','OB/GYN','OB/GYN','5678901234',TRUE),
('PROV-006','Dr. David Lee','Orthopedic Surgery','Orthopedics','6789012345',TRUE),
('PROV-007','Dr. Nina Patel','Psychiatry','Behavioral Health','7890123456',TRUE),
('PROV-008','Dr. Robert Garcia','Nephrology','Nephrology','8901234567',TRUE);

-- ============================================================
-- 4. CHECKPOINT: Verify setup
-- ============================================================
SELECT 'PATIENT_DIM' AS TBL, COUNT(*) AS ROWS FROM BUH_HOL.RAW.PATIENT_DIM
UNION ALL SELECT 'ENCOUNTER_FACT', COUNT(*) FROM BUH_HOL.RAW.ENCOUNTER_FACT
UNION ALL SELECT 'LAB_RESULTS', COUNT(*) FROM BUH_HOL.RAW.LAB_RESULTS
UNION ALL SELECT 'PROVIDER_DIM', COUNT(*) FROM BUH_HOL.RAW.PROVIDER_DIM
ORDER BY TBL;

/*
  EXPECTED OUTPUT:
  ENCOUNTER_FACT   10
  LAB_RESULTS      10
  PATIENT_DIM       8
  PROVIDER_DIM      8
*/
