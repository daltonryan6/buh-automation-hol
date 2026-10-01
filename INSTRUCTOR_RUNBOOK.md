# Instructor Runbook - BUH Hands-On Lab

## Pre-Session Checklist

- [ ] Snowflake trial or existing account accessible for all attendees
- [ ] Each attendee has ACCOUNTADMIN or equivalent privileges
- [ ] Repository accessible (GitHub link shared, or scripts downloaded)
- [ ] Test run: execute 00_setup.sql through 05 end-to-end in a clean account
- [ ] Screen share and projection ready
- [ ] For Power BI/Iceberg walkthrough: have screenshots or a pre-built demo ready if you want to show the Fabric side (not required for trial accounts)

## Timing Guide

| Time | Module | Script | Facilitator Notes |
|------|--------|--------|-------------------|
| 0:00-0:10 | Welcome + Setup | 00_setup.sql | Everyone runs setup together. Verify row counts. |
| 0:10-0:25 | Shared Workspaces | 01_workspaces_and_git.sql | This is a walkthrough/discussion. Show the Git integration in Snowsight if you have one configured. The SQL in the script is commented-out reference material. |
| 0:25-0:55 | Dynamic Tables | 02_dynamic_tables.sql | The centerpiece. Let participants build CURATED and GOLD layers. Insert the new patient and wait for refresh. Monitor refresh history. |
| 0:55-1:20 | Power BI/Iceberg/Fabric | 03_powerbi_iceberg_fabric.sql | Mixed: Iceberg table creation is hands-on, Power BI connection options and Fabric cost discussion is walkthrough. The Iceberg CTAS may not work on all trial editions without an external volume; have the fallback discussion ready. |
| 1:20-1:45 | Tags + Governance | 04_tags_and_governance.sql | Hands-on: create tags, apply to columns, query TAG_REFERENCES, test masking with POLICY_CONTEXT. Key moment: tag-based masking applies to all columns at once. |
| 1:45-1:55 | Putting it together | 05_putting_it_together.sql | Quick verification + next steps discussion. |
| 1:55-2:00 | Recap | 06_cleanup.sql | Summarize. Offer cleanup script. |

## Common Issues and Fallbacks

| Issue | Fix |
|-------|-----|
| "Warehouse does not exist" | Setup script creates COMPUTE_WH. If it fails, the user may not have ACCOUNTADMIN. |
| Dynamic table shows 0 rows | Dynamic tables may take up to TARGET_LAG to populate. Wait 1 minute and re-query. Check INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY() for errors. |
| Iceberg CTAS fails with "external volume" error | Managed Iceberg tables (CATALOG='SNOWFLAKE' with empty EXTERNAL_VOLUME) may require specific account settings. Fall back to the walkthrough discussion and skip the hands-on Iceberg creation. |
| TAG_REFERENCES returns 0 rows | ACCOUNT_USAGE views have latency (up to 2 hours). Use INFORMATION_SCHEMA.TAG_REFERENCES function instead for real-time results, or use SHOW TAGS and manual verification. |
| Masking not visible when testing roles | On a trial account, EXECUTE USING POLICY_CONTEXT simulates role context correctly. If that syntax is not available, create test users (see below). |
| POLICY_CONTEXT not available | Create test users: `CREATE USER lab_analyst_test PASSWORD='Test1234!' DEFAULT_ROLE=BUH_LAB_ANALYST; GRANT ROLE BUH_LAB_ANALYST TO USER lab_analyst_test;` and log in as that user. |
| Tag-based masking policy conflict | If a column already has a direct masking policy, you cannot also apply a tag-based policy. The script applies SSN and DOB masks directly and PII_STRING via tag. |

## Key Discussion Points by Module

### Shared Workspaces
- "How does your team share SQL today?" (usually Slack, email, file shares)
- Git workspaces replace that with versioned, reviewable, deployable code
- Cortex Code adds AI-assisted SQL development on top

### Dynamic Tables
- "How many scheduled scripts do you maintain today?"
- Dynamic tables replace orchestration complexity with declarative SQL
- TARGET_LAG is the key design decision - not "when to run" but "how fresh"
- Incremental refresh means Snowflake only processes changed data

### Power BI / Iceberg / Fabric
- "Microsoft is recommending Iceberg for your gold layer" - this is the right pattern
- The cost play: keep pipeline in Snowflake (where you have expertise), expose only GOLD as Iceberg
- Fabric CU overconsumption happens when you run too many workloads on undersized capacity
- Purview can scan Snowflake directly - tags and labels are separate systems that need alignment

### Tags and Governance
- Tags are metadata, not access control - they DESCRIBE what data is
- Tag-based masking ENFORCES policy based on tags - one policy protects all columns with that tag
- SYSTEM$CLASSIFY automates PII detection so you do not tag 500 columns by hand
- For BUH: tags + classification + masking is the foundation; Purview alignment is a follow-on project

## Teardown

After the session, each attendee runs `scripts/06_cleanup.sql`. Important: unset the warehouse tag before dropping the database, or the tag reference will be orphaned.
