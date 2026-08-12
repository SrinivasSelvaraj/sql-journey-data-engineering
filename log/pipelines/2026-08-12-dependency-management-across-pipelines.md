---
date: 2026-08-12
phase: pipelines
topic: Dependency management across pipelines
---

# Dependency management across pipelines

*Pipelines and orchestration*

## Concept

Dependency management across pipelines defines the order, timing, and conditions under which data jobs execute. Without it, downstream jobs consume incomplete or stale data, causing silent failures that corrupt analytics and reports. Dependencies are not just "run job B after job A"—they include data freshness guarantees, schema contracts, and idempotency requirements that let you safely rerun failed jobs without cascading corruption.

When pipelines are loosely coupled, a single upstream failure (extraction stall, transformation bug, load timeout) forces manual intervention across multiple downstream jobs. Strong dependency management makes this visible: job orchestrators (Airflow, dbt Cloud, Dagster) detect failures and automatically halt dependent work, then replay only what's necessary when the root cause is fixed.

Without explicit dependencies, teams often resort to crude workarounds: scheduled buffer windows between jobs, monitoring alerts that nobody trusts, or manual coordination. These hide the real problem—they don't prevent it.

## Practice

**Problem:** The `job_postings_fact` table depends on three upstream sources: a raw job feeds extraction (daily, 6 AM), a salary standardization lookup (weekly, Tuesday 2 AM), and a location geocoding service (runs ad-hoc, SLA 24 hours). Your fact table must only load when *all three* are fresh. Currently, you have no explicit checks; jobs run on fixed schedules and sometimes load with missing location codes.

**Solution:**

```sql
-- Materialized view that enforces dependency freshness before fact table loads
CREATE OR REPLACE VIEW job_postings_staging AS
WITH freshness_checks AS (
  SELECT
    CASE 
      WHEN MAX(loaded_at) < CURRENT_TIMESTAMP - INTERVAL '25 hours' 
        THEN 'stale_location_geocoding'
      WHEN (SELECT MAX(loaded_at) FROM raw.job_feeds) < CURRENT_TIMESTAMP - INTERVAL '30 hours'
        THEN 'stale_job_feeds'
      WHEN (SELECT MAX(loaded_at) FROM lookup.salary_standardization) < CURRENT_TIMESTAMP - INTERVAL '8 days'
        THEN 'stale_salary_lookup'
      ELSE 'ready'
    END AS dependency_status,
    MAX(loaded_at) AS location_freshness
  FROM raw.location_geocoding
)
SELECT
  jf.job_id,
  jf.job_title_short,
  COALESCE(ss.salary_year_avg, jf.salary_year_avg) AS salary_year_avg,
  jf.job_work_from_home,
  jf.job_posted_date,
  lg.location_standardized AS job_location
FROM raw.job_feeds jf
LEFT JOIN lookup.salary_standardization ss ON jf.job_title = ss.job_title_raw
LEFT JOIN raw.location_geocoding lg ON jf.job_location_raw = lg.location_raw
CROSS JOIN freshness_checks
WHERE freshness_checks.dependency_status = 'ready'
  AND jf.loaded_at = (SELECT MAX(loaded_at) FROM raw.job_feeds)
  AND ss.loaded_at = (SELECT MAX(loaded_at) FROM lookup.salary_standardization);

-- Orchestrator-level check (pseudocode for Airflow/dbt)
-- This runs before the fact table is built
SELECT dependency_status FROM job_postings_staging LIMIT 1;
-- If result != 'ready', fail the task with clear message
```

## Notes

- **Idempotency trap:** Dependencies only work if upstream jobs are idempotent—re-running a job with the same input produces identical output. If extraction jobs append instead of upsert, your dependency checks pass but your fact table has duplicates.

- **Freshness vs. completion:** A job finishing quickly doesn't mean it's right. Pair dependency timing checks with data quality assertions (row counts, schema validation, null checks) to catch silent failures.

- **Cross-pipeline communication:** Use metadata tables (load timestamps, row counts, checksum hashes) to communicate freshness upstream. Don't rely on file modification times or wall-clock assumptions.

- **Blast radius:** Think about what breaks if one dependency fails. A weekly lookup delay should not block daily fact loads; use fallback logic or cached values. Make dependencies granular, not monolithic.

- **Testing dependencies locally:** Simulate stale upstream data in your dev environment by backdating `loaded_at` timestamps. Verify your pipelines fail clearly and document the recovery runbook.
