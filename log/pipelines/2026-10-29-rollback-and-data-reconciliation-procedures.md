---
date: 2026-10-29
phase: pipelines
topic: Rollback and data reconciliation procedures
---

# Rollback and data reconciliation procedures

*Pipelines and orchestration*

## Concept

Rollback and data reconciliation procedures are mechanisms that detect failed pipeline runs and either revert changes to a known-good state or identify and fix discrepancies without manual intervention. A rollback restores data to its previous snapshot when a transformation fails midway; reconciliation compares source and target record counts, checksums, or key metrics to confirm pipeline integrity after completion. These matter because partial writes corrupt downstream analytics—a job posting pipeline that loads 80% of records silently will cause incorrect salary aggregations and recruitment dashboards to drift from reality. Without them, you discover data corruption weeks later through user complaints rather than immediately when the job posting feed fails to fully sync.

## Practice

**Problem:** Your daily job_postings_fact load runs at 06:00 UTC, but a schema validation error occurs after inserting 45,000 of 50,000 records. The pipeline halts, leaving inconsistent state. The next run at 18:00 UTC inserts the remaining 5,000, but now you have duplicate dates and gaps in job_posted_date. How do you detect and fix this?

```sql
-- 1. Reconciliation check: compare expected vs actual counts
WITH source_count AS (
  SELECT COUNT(*) as expected FROM raw_job_postings 
  WHERE ingestion_date = CURRENT_DATE
),
target_count AS (
  SELECT COUNT(*) as actual FROM job_postings_fact 
  WHERE job_posted_date = CURRENT_DATE
),
reconciliation AS (
  SELECT 
    s.expected, 
    t.actual,
    CASE WHEN s.expected = t.actual THEN 'PASS' ELSE 'FAIL' END as status
  FROM source_count s, target_count t
)
SELECT * FROM reconciliation;

-- 2. If FAIL: rollback and rerun
DELETE FROM job_postings_fact 
WHERE job_posted_date = CURRENT_DATE;

-- 3. Identify gaps with checksum validation
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  ROW_NUMBER() OVER (ORDER BY job_posted_date, job_id) as expected_sequence
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE
ORDER BY job_posted_date;

-- 4. Reinsert full batch atomically (idempotent)
INSERT INTO job_postings_fact 
SELECT * FROM raw_job_postings 
WHERE ingestion_date = CURRENT_DATE
ON CONFLICT (job_id) DO UPDATE SET 
  job_title_short = EXCLUDED.job_title_short;
```

## Notes

- **Idempotency first:** Use `ON CONFLICT DO UPDATE` or partition-based delete–insert so reruns don't create duplicates; avoid append-only without upsert logic.
- **Fail loudly, not silently:** Reconciliation checks (row count, hash of key fields, freshness timestamp) must raise exceptions that trigger orchestration alerts—silent mismatches are the worst outcome.
- **Checkpoint and state:** Store pipeline state (last processed timestamp, record count) in a control table so rollback knows what to revert; avoid assumptions about "last night's load."
- **Adjacent: Idempotency, data quality gates, and orchestration monitoring** (Airflow/Dagster sensors); reconciliation is useless if no one is alerted or if the pipeline reruns with the same bug.
- **Revisit:** How to automate reconciliation thresholds (e.g., fail if <95% of expected records) and design rollback windows for high-volume fact tables without locking production.
