---
date: 2026-08-23
phase: pipelines
topic: Runbooks as code and automated remediation
---

# Runbooks as code and automated remediation

*Pipelines and orchestration*

## Concept

Runbooks as code means encoding operational procedures—monitoring checks, alerting rules, and remediation logic—into version-controlled, executable definitions rather than static documents or manual processes. When a pipeline fails, a runbook-as-code system automatically diagnoses the failure (data quality checks, schema validation, upstream dependency status), logs findings, and executes fixes (retry with backoff, backfill missing dates, quarantine bad records) without human intervention. This matters because silent failures propagate downstream, cascading into corrupted analytics and broken dashboards; automated remediation keeps pipelines resilient during the inevitable transient failures, network hiccups, and late-arriving data that plague production systems.

Without runbooks as code, you either have runbooks no one reads, or you wake up at 3 AM to manually re-run jobs, restart services, and delete duplicate records. Worse, each remediation is ad-hoc and undocumented, so the next engineer learns nothing. With runbooks as code, failures become observable patterns: you can see which checks fail most often, which remediations succeed, and where your pipeline is actually brittle.

## Practice

**Problem:** `job_postings_fact` loads daily from an external API. Some days the API returns nulls for `salary_year_avg`; some days `job_posted_date` is missing entirely. You need a runbook that detects these failures, quarantines bad rows, logs the issue, and backfills from yesterday's snapshot if today's data quality is too poor.

```sql
-- Runbook as code: detect, remediate, and log
WITH quality_checks AS (
  SELECT
    COUNT(*) as total_rows,
    COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) as null_salary_count,
    COUNT(CASE WHEN job_posted_date IS NULL THEN 1 END) as null_date_count,
    CURRENT_DATE() as check_date
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE() - 1
),
should_remediate AS (
  SELECT
    *,
    CASE 
      WHEN null_salary_count / total_rows > 0.3 
        OR null_date_count / total_rows > 0.1 
      THEN TRUE 
      ELSE FALSE 
    END as trigger_backfill
  FROM quality_checks
),
remediate AS (
  DELETE FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE() 
    AND (salary_year_avg IS NULL OR job_posted_date IS NULL)
)
INSERT INTO job_postings_fact
SELECT * FROM job_postings_fact_snapshot
WHERE snapshot_date = CURRENT_DATE() - 1
  AND (SELECT trigger_backfill FROM should_remediate)
;

-- Log the runbook execution
INSERT INTO pipeline_runbook_log (runbook_name, check_date, rows_deleted, rows_restored, status)
SELECT
  'job_postings_daily_quality',
  check_date,
  (SELECT COUNT(*) FROM remediate),
  CASE WHEN (SELECT trigger_backfill FROM should_remediate) THEN (SELECT COUNT(*) FROM job_postings_fact_snapshot WHERE snapshot_date = CURRENT_DATE() - 1) ELSE 0 END,
  CASE WHEN (SELECT trigger_backfill FROM should_remediate) THEN 'BACKFILLED' ELSE 'PASSED' END
FROM should_remediate
;
```

## Notes

- **Idempotency is critical:** runbooks will retry; if a runbook deletes and re-inserts the same records twice, you need idempotent logic (upserts, partition overwrites) or you'll corrupt your data further.
- **Observability first:** before adding auto-remediation, instrument every check. Log what you detect, why you decided to remediate, and what you actually changed. Future you will need this audit trail.
- **Thresholds are opinions:** deciding "30% nulls = trigger backfill" is a business decision, not a technical one. Runbooks should parameterize thresholds so you can tune them without redeploying code.
- **Adjacent: circuit breakers and graceful degradation.** Runbooks handle transient issues; circuit breakers prevent cascading failures by stopping a pipeline before it corrupts downstream consumers. Combine them.
- **Revisit:** test your runbooks as thoroughly as your data pipelines. A broken remediation is worse than no remediation. Chaos-test by injecting failures into staging.
