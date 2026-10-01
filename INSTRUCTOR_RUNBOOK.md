# Instructor Runbook - BUH Automation & Governance Lab

## Pre-Session Checklist

- [ ] Snowflake account provisioned and accessible for all attendees
- [ ] Each attendee has ACCOUNTADMIN or equivalent privileges
- [ ] COMPUTE_WH warehouse exists (or edit 00_setup.sql)
- [ ] Repository cloned/available in Git workspace or downloaded
- [ ] Test run: execute 00_setup.sql through 04 end-to-end in a clean account
- [ ] Cortex AI Functions availability confirmed (or plan to use fallbacks in Script 05)
- [ ] Screen share and projection ready

## Timing Guide

| Time | Module | Script | Facilitator Notes |
|------|--------|--------|-------------------|
| 0:00-0:10 | Welcome | - | Frame the goal: "By the end of this session, you will have replaced a hand-coded import with a parameterized, observable, governed pipeline." Show the before/after. |
| 0:10-0:20 | Setup | 00_setup.sql | Everyone runs setup together. Watch for warehouse/role errors. Checkpoint: verify row counts match expected output. |
| 0:20-0:45 | Parameterized imports | 01_parameterized_imports.sql | Walk through Part A (the problem) first. Let participants build the procedure in Part C. Key moment: show the config table driving all imports. |
| 0:45-1:05 | Vendor ingestion | 02_vendor_ingestion.sql | Run good batch first, then drifted (watch the WARN log), then invalid (watch quarantine). This is the "aha" moment for resilience. |
| 1:05-1:25 | Logging | 03_logging_and_monitoring.sql | Quick module - mostly querying what already exists. The BATCH_HEALTH view is the payoff. Discuss event tables and alerts as production next-steps. |
| 1:25-1:45 | Governance | 04_governance_rbac_masking.sql | Most interactive module. Have participants switch roles and compare results. The SSN last-4 vs full vs hidden comparison lands well. |
| 1:45-1:55 | AI capstone | 05_ai_multimodal_capstone.sql | Optional. If Cortex is available, run live. If not, use fallback queries and discuss the pattern. Focus on "AI fits INTO the pipeline." |
| 1:55-2:00 | Recap | - | Summarize the four layers: Automate - Validate - Observe - Govern. Offer cleanup script. Discuss next steps. |

## Common Issues and Fallbacks

| Issue | Fix |
|-------|-----|
| "Warehouse does not exist" | `CREATE WAREHOUSE COMPUTE_WH WAREHOUSE_SIZE='XSMALL' AUTO_SUSPEND=60 AUTO_RESUME=TRUE;` |
| "Insufficient privileges" on role switch | Ensure `GRANT ROLE BUH_LAB_X TO USER <username>;` was run. The setup script grants to ACCOUNTADMIN hierarchy, but individual users may need direct grants. |
| Masking not visible when testing roles | If the current user has ACCOUNTADMIN, IS_ROLE_IN_SESSION('BUH_LAB_ADMIN') may resolve to TRUE even when using BUH_LAB_ANALYST. To demonstrate, create a separate test user: `CREATE USER lab_analyst_test PASSWORD='Test1234!' DEFAULT_ROLE=BUH_LAB_ANALYST; GRANT ROLE BUH_LAB_ANALYST TO USER lab_analyst_test;` and log in as that user, or use `EXECUTE AS` to test. |
| CLINICIAN role cannot see CURATED tables | Run future grants: `GRANT SELECT ON FUTURE TABLES IN SCHEMA BUH_AUTOMATION_LAB.CURATED TO ROLE BUH_LAB_CLINICIAN;` |
| AI_COMPLETE not available | Use the fallback queries (commented out in Script 05). The learning point is the pattern, not the model output. |
| Validation UDTF returns unexpected results | Check that the VENDOR_LAB_EXPECTED_SCHEMA data matches. Re-run 00_setup.sql to reset. |
| Duplicate rows after re-run of vendor batch | Expected behavior - discuss idempotency in Part F of Script 02. Reset with DELETE WHERE BATCH_ID = 'X'. |

## Extension Ideas (if time permits or for follow-up)

1. **Idempotent vendor ingestion**: Modify PROCESS_VENDOR_BATCH to DELETE+INSERT or use MERGE
2. **Event tables**: Create an actual event table and emit SYSTEM$LOG calls from procedures
3. **Scheduled alerts**: Create an alert that watches RUN_LOG for ERROR entries
4. **Tag-based masking**: Create tags, run SYSTEM$CLASSIFY, attach policies to tags
5. **Task scheduling**: Wrap RUN_ALL_IMPORTS in a Snowflake Task on a CRON schedule
6. **Dynamic tables**: Replace CTAS imports with dynamic tables for incremental refresh

## Teardown

After the session, each attendee runs `scripts/06_cleanup.sql` to drop the lab database and roles. If using a shared account, only one person should run cleanup.
