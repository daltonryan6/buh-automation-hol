/*=============================================================================
  Brown University Health - Automation & Governance Hands-On Lab
  Script 05: AI & Multimodal Capstone (Optional)
  
  GOAL: Use Cortex AI functions to reduce manual annotation effort
        on clinical notes, image metadata, and omics cataloging.
        All steps have deterministic fallbacks if Cortex is
        unavailable or not enabled.
  
  TIME: ~10 minutes
  PREREQUISITE: Run 00_setup.sql (creates sample data)
  NOTE: AI_COMPLETE requires Cortex AI Functions to be enabled.
        If not available, the fallback queries still demonstrate
        the pattern with static results.
=============================================================================*/

USE DATABASE BUH_AUTOMATION_LAB;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================
-- PART A: Summarize clinical notes (AI-assisted)
-- ============================================================

-- See the raw notes
SELECT NOTE_ID, NOTE_TYPE, LEFT(NOTE_TEXT, 120) || '...' AS PREVIEW
FROM RAW.CLINICAL_NOTES;

-- Use SNOWFLAKE.CORTEX.AI_COMPLETE to generate a structured summary.
-- If Cortex is not available, skip to the fallback below.

-- >>> TRY THIS FIRST <<<
SELECT
    NOTE_ID,
    NOTE_TYPE,
    SNOWFLAKE.CORTEX.AI_COMPLETE(
        'llama3.1-8b',
        'Summarize this clinical note in 2-3 sentences. Extract: primary diagnosis, key findings, and plan. Note: ' || NOTE_TEXT
    ) AS AI_SUMMARY
FROM RAW.CLINICAL_NOTES;

-- >>> FALLBACK if Cortex is not enabled <<<
-- SELECT
--     NOTE_ID,
--     NOTE_TYPE,
--     CASE NOTE_ID
--         WHEN 'N400001' THEN 'Dx: STEMI. Findings: Troponin 2.45, cath with DES to LAD. Plan: Dual antiplatelet, statin, beta-blocker, ACEi, cardiac rehab in 2 weeks.'
--         WHEN 'N400002' THEN 'Dx: NSCLC stage IIIA. Findings: 4.2cm RUL mass, mediastinal LAD. Plan: Await PET, discuss chemoradiation vs surgery.'
--         WHEN 'N400003' THEN 'Dx: MDD moderate. Findings: PHQ-9 16, sleep/appetite/anhedonia. Plan: Sertraline 50mg, therapy referral, follow-up 4 weeks.'
--     END AS AI_SUMMARY
-- FROM RAW.CLINICAL_NOTES;

-- ============================================================
-- PART B: Extract structured fields from notes
-- ============================================================

-- Use AI_EXTRACT to pull structured data from free text
-- >>> TRY THIS FIRST <<<
SELECT
    NOTE_ID,
    SNOWFLAKE.CORTEX.AI_EXTRACT(
        NOTE_TEXT,
        ARRAY_CONSTRUCT('primary_diagnosis', 'medications', 'follow_up_plan')
    ) AS EXTRACTED
FROM RAW.CLINICAL_NOTES;

-- >>> FALLBACK <<<
-- SELECT
--     NOTE_ID,
--     CASE NOTE_ID
--         WHEN 'N400001' THEN PARSE_JSON('{"primary_diagnosis":"STEMI","medications":"aspirin, clopidogrel, atorvastatin, metoprolol, lisinopril","follow_up_plan":"Cardiology in 2 weeks, cardiac rehab"}')
--         WHEN 'N400002' THEN PARSE_JSON('{"primary_diagnosis":"NSCLC stage IIIA","medications":"current pain regimen","follow_up_plan":"PET scan, then treatment decision"}')
--         WHEN 'N400003' THEN PARSE_JSON('{"primary_diagnosis":"MDD moderate","medications":"sertraline 50mg","follow_up_plan":"Therapy referral, follow-up 4 weeks"}')
--     END AS EXTRACTED
-- FROM RAW.CLINICAL_NOTES;

-- ============================================================
-- PART C: Generate image descriptions for catalog
-- ============================================================

-- Image metadata currently has no AI_DESCRIPTION
SELECT IMAGE_ID, MODALITY, BODY_PART, AI_DESCRIPTION FROM RAW.IMAGE_METADATA;

-- In production, you would pass the actual image through a
-- multimodal model. Here we demonstrate the metadata annotation
-- pattern using the text context we have.

-- >>> TRY THIS FIRST <<<
UPDATE RAW.IMAGE_METADATA
SET AI_DESCRIPTION = SNOWFLAKE.CORTEX.AI_COMPLETE(
    'llama3.1-8b',
    'Generate a brief radiology catalog description for an image with these attributes. '
    || 'Modality: ' || MODALITY
    || ', Body part: ' || BODY_PART
    || ', Patient context: encounter ' || ENCOUNTER_ID
    || '. Keep it to 1-2 sentences suitable for a searchable catalog.'
);

SELECT IMAGE_ID, MODALITY, BODY_PART, AI_DESCRIPTION FROM RAW.IMAGE_METADATA;

-- >>> FALLBACK <<<
-- UPDATE RAW.IMAGE_METADATA
-- SET AI_DESCRIPTION = CASE IMAGE_ID
--     WHEN 'IMG-001' THEN 'Coronary angiography of the heart during cardiac catheterization for acute STEMI evaluation.'
--     WHEN 'IMG-002' THEN 'AP and lateral X-ray of the left wrist for acute distal radius fracture assessment.'
--     WHEN 'IMG-003' THEN 'CT chest with IV contrast for staging of newly diagnosed lung malignancy, right upper lobe.'
-- END;

-- ============================================================
-- PART D: Omics metadata enrichment
-- ============================================================

-- Quick classification of omics samples
SELECT
    SAMPLE_ID,
    PAT_ID,
    ASSAY_TYPE,
    PANEL_NAME,
    VARIANTS_DETECTED,
    CASE
        WHEN VARIANTS_DETECTED > 10 THEN 'Complex - recommend genomics board review'
        WHEN VARIANTS_DETECTED > 5  THEN 'Moderate - standard oncology review'
        ELSE 'Simple - routine follow-up'
    END AS REVIEW_RECOMMENDATION
FROM RAW.OMICS_METADATA;

-- ============================================================
-- PART E: Discussion - where AI fits in the pipeline
-- ============================================================

-- Key takeaway: AI is not a separate initiative. It fits INTO
-- the pipeline you already built:
--
-- 1. PARAMETERIZED IMPORTS (Script 01):
--    AI_COMPLETE can generate column descriptions for your data catalog
--    AI_EXTRACT can parse unstructured fields during import
--
-- 2. VENDOR INGESTION (Script 02):
--    AI_CLASSIFY can categorize vendor content
--    AI_EXTRACT can normalize inconsistent vendor formats
--
-- 3. LOGGING (Script 03):
--    AI_SUMMARIZE on error logs to surface patterns
--    AI_COMPLETE to suggest remediation steps
--
-- 4. GOVERNANCE (Script 04):
--    SYSTEM$CLASSIFY to detect PII automatically
--    AI-generated sensitivity labels for tag-based masking
--
-- The work you did in Scripts 01-04 is the foundation.
-- AI accelerates it; it does not replace it.

-- ============================================================
-- CHECKPOINT: You should see
--   - AI-generated summaries of clinical notes (or static fallbacks)
--   - Structured extraction of diagnoses/meds/plans
--   - Image metadata descriptions populated
--   - Omics review recommendations
-- ============================================================
