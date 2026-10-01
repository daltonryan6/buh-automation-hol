# Brown University Health - Automation & Governance Hands-On Lab

## From Hand-Coded Imports to Production-Grade Pipelines - in 2 Hours

### Overview

This lab walks through the real workflow of replacing hand-coded Epic Clarity table imports with parameterized, observable, governed pipelines in Snowflake. Instead of a feature tour, you will build one end-to-end import workflow and watch it handle unexpected input, log structured events, and enforce data governance policies.

### What you will build

1. A configuration-driven stored procedure that imports any Clarity table from a single config row
2. A resilient vendor-file ingestion pipeline with validation, quarantine, and safe re-run
3. Centralized run logging with structured info/warn/error events
4. Reusable masking policies and row-access controls on sensitive fields
5. (Optional) AI-assisted annotation of clinical notes and multimodal metadata

### Prerequisites

- A Snowflake account (trial or existing) with ACCOUNTADMIN or a role that can create databases, warehouses, and roles
- A warehouse named `COMPUTE_WH` (or edit the setup script to match yours)
- Cortex Code or any SQL worksheet environment

### Quick start

1. Clone this repository into a Snowflake Git workspace or download the scripts folder
2. Open `scripts/00_setup.sql` and run it end-to-end - it creates the lab database, schemas, roles, synthetic data, and sample vendor files
3. Follow the guided website (open `index.html` locally) or work through the numbered scripts in order

### Session flow (120 minutes)

| Time | Module | Script |
|------|--------|--------|
| 0-10 | Welcome and workspace setup | `00_setup.sql` |
| 10-20 | Run setup, explore synthetic data | `00_setup.sql` |
| 20-45 | Parameterized imports and reusable code | `01_parameterized_imports.sql` |
| 45-65 | Resilient vendor file ingestion | `02_vendor_ingestion.sql` |
| 65-85 | Centralized logging and error reporting | `03_logging_and_monitoring.sql` |
| 85-105 | Governance, RBAC, and masking | `04_governance_rbac_masking.sql` |
| 105-115 | AI and multimodal capstone (optional) | `05_ai_multimodal_capstone.sql` |
| 115-120 | Recap and cleanup | `06_cleanup.sql` |

### Repository structure

```
buh-automation-hol/
  index.html              -- Guided walkthrough website
  assets/
    styles.css            -- Site styling
    lab.js                -- Navigation, copy, dark mode
  scripts/
    00_setup.sql          -- Database, schemas, roles, synthetic data
    01_parameterized_imports.sql
    02_vendor_ingestion.sql
    03_logging_and_monitoring.sql
    04_governance_rbac_masking.sql
    05_ai_multimodal_capstone.sql
    06_cleanup.sql
  INSTRUCTOR_RUNBOOK.md   -- Timing, fallbacks, privilege checklist
```

### Cleanup

Run `scripts/06_cleanup.sql` to drop the lab database and roles when finished.
