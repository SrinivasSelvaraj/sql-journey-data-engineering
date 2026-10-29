---
date: 2026-10-29
phase: pipelines
topic: Documentation and runbook generation
---

# Documentation and runbook generation

*Pipelines and orchestration*

## Concept

Documentation and runbook generation transform pipelines from black boxes into self-explaining systems. A runbook is executable documentation—it captures *why* a pipeline exists, *what* it does, *when* it fails, and *how* to fix it. Without runbooks, you spend hours reconstructing context after a 3am failure; with them, operators follow steps without deep domain knowledge.

This matters most when pipelines touch critical data or when knowledge lives only in one person's head. A runbook should include: data lineage (what tables feed this pipeline), failure modes (what actually breaks and why), recovery procedures (which steps to rerun, in what order), and SLOs (when should this complete, what's acceptable lateness). Generate these from pipeline metadata—table schemas, dependencies, test assertions—so they stay in sync with code changes.

Without documentation, junior engineers hesitate to rerun failed jobs (risking duplicate data or stale results), operations teams can't triage issues, and on-call rotations become a liability. A runbook that says "restart from `staging.job_postings_raw` if upstream API returned 500" enables confident recovery.

## Practice

**Problem:** Your job postings pipeline has three stages: fetch raw postings, deduplicate and cleanse, aggregate salary statistics by job_title_short. The cleanse step failed at 2am due to a malformed date in job_posted_date. You need to document the recovery procedure and generate a runbook entry that prevents knowledge loss.

```sql
-- RUNBOOK: job_postings_daily_pipeline
-- Purpose: Ingest job postings, cleanse, and compute salary facts
-- SLO: Complete by 06:00 UTC; fail if job_postings_raw is >2 hours stale

-- Stage 1: Raw ingest (external, idempotent by job_id)
-- Failure mode: API timeout or malformed JSON → raw table has nulls in job_posted_date
-- Recovery: Rerun from here only if you've fixed upstream

CREATE OR REPLACE TABLE raw.job_postings_raw AS
SELECT job_id, job_title, salary, work_from_home, posted_date, location
FROM external_api_fetch(date = CURRENT_DATE);

-- Stage 2: Cleanse (idempotent; validates date format)
-- Failure mode: Unparseable dates → pipeline halts
-- Recovery: Rerun this stage after upstream confirms data quality
CREATE OR REPLACE TABLE staging.job_postings_clean AS
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  work_from_home AS job_work_from_home,
  TRY_CAST(posted_date AS DATE) AS job_posted_date,
  location AS job_location
FROM raw.job_postings_raw
WHERE TRY_CAST(posted_date AS DATE) IS NOT NULL
  AND salary_year_avg > 0;

-- Assertion: Validate row count didn't drop >10% (detect silent failures)
ASSERT (
  SELECT COUNT(*) FROM staging.job_postings_clean 
) >= (
  SELECT COUNT(*) * 0.9 FROM raw.job_postings_raw
);

-- Stage 3: Fact table (safe to rerun; uses INSERT OVERWRITE)
-- Failure mode: Duplicate aggregations if run twice
-- Recovery: Safe to rerun; overwrites yesterday's partition
CREATE OR REPLACE TABLE analytics.job_postings_fact AS
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM staging.job_postings_clean
WHERE job_posted_date = CURRENT_DATE - 1;

-- IF STAGE 2 FAILS: Check raw data → fix upstream → rerun stage 2 only
-- IF STAGE 3 FAILS: Safe to retry; partition is overwritten
-- DO NOT rerun stage 1 unless upstream confirms new data is available
```

## Notes

- **Embed assertions in pipelines, not just comments.** `ASSERT` statements fail loudly and document contracts; a comment saying "must have >90% rows" will be ignored and forgotten.
- **Idempotency is documentation's prerequisite.** If rerunning a stage has side effects (duplicate rows, overwritten intermediate tables), your runbook becomes unreliable. Use `INSERT OVERWRITE PARTITION` or merge logic, not append-only inserts.
- **Connect to data lineage tools.** Generate runbooks from DAG metadata (dbt, Airflow) so they auto-update when dependencies shift. A static runbook that contradicts the actual pipeline is worse than none.
- **Version runbooks alongside code.** Store runbook templates in version control; trigger generation on PR merges so they never lag behind schema or job changes.
- **Failure modes are the runbook's core.** Rather than generic instructions, list specific failures: "If job_posted_date contains future dates → rerun cleanse after upstream backfill" is far more useful than "Check data quality."
