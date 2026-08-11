---
date: 2026-08-11
phase: pipelines
topic: Idempotency as a design requirement
---

# Idempotency as a design requirement

*Pipelines and orchestration*

## Concept

Idempotency means running the same operation multiple times produces the same result as running it once. In data pipelines, this is non-negotiable because retries, reruns, and network failures are inevitable. Without idempotency, a failed job that reruns will duplicate data, corrupt aggregates, or leave the warehouse in an inconsistent state.

Idempotency matters most at the point where external data enters your system and where state is persisted (inserts, updates, deletes). A pipeline that reads from an API, transforms data, and loads to a fact table must handle the scenario where the API call succeeds but the confirmation never returns—so the job reruns and tries to load the same records again.

Common breakage: incremental loads that track "last processed timestamp" but don't handle clock skew or replay; upserts without unique constraints; intermediate tables that accumulate duplicates on each retry; aggregations that sum the same rows twice. The result is silent data corruption—your metrics drift without alerting you.

## Practice

**Problem:** Your `job_postings_fact` table is loaded nightly from an external API. The pipeline extracts jobs posted in the last 24 hours, but the API occasionally times out mid-response. When you retry, some jobs are fetched again. After three retries on a Tuesday night, you notice salary_year_avg has been summed multiple times in downstream aggregations.

**Solution:** Use a merge (upsert) pattern with a unique business key and load timestamp tracking:

```sql
MERGE INTO job_postings_fact AS target
USING staging_job_postings AS source
ON target.job_id = source.job_id
  AND target.job_posted_date = source.job_posted_date
WHEN MATCHED 
  AND source.load_timestamp > target.load_timestamp
THEN UPDATE SET 
  job_title_short = source.job_title_short,
  salary_year_avg = source.salary_year_avg,
  job_work_from_home = source.job_work_from_home,
  job_location = source.job_location,
  load_timestamp = source.load_timestamp
WHEN NOT MATCHED
THEN INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, load_timestamp)
VALUES (source.job_id, source.job_title_short, source.salary_year_avg, source.job_work_from_home, source.job_posted_date, source.job_location, source.load_timestamp);
```

The composite key `(job_id, job_posted_date)` ensures duplicates from retries match existing rows; the `load_timestamp` guard prevents stale data from overwriting fresh data.

## Notes

- **Timestamp guards are essential**: always track when a record was loaded or processed. This prevents old data from overwriting newer state during retries or out-of-order reprocessing.
- **Staging tables + merge beats raw inserts**: load to a temporary table first, then merge. This isolates retry logic and makes the final write atomic.
- **Idempotency ≠ deduplication**: dedup removes *exact* duplicates; idempotency ensures the *outcome* is the same. You can have duplicates in staging as long as the merge produces one canonical row per key.
- **Connects to**: distributed transaction semantics (exactly-once vs. at-least-once), orchestration retry policies (Airflow `max_tries`), and monitoring (alert on row count deltas before/after merge).
- **Revisit when**: designing CDC pipelines, handling late-arriving data, or building cross-system consistency checks. Also critical when external dependencies (APIs, webhooks) have flaky networks.
