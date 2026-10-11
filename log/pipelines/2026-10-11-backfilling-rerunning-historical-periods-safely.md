---
date: 2026-10-11
phase: pipelines
topic: Backfilling: rerunning historical periods safely
---

# Backfilling: rerunning historical periods safely

*Pipelines and orchestration*

## Concept

Backfilling is rerunning a pipeline for historical time periods after code changes, schema updates, or bug fixes. It differs from regular incremental runs because it must safely overwrite or upsert old data without breaking downstream consumers or creating duplicates. Without careful backfilling strategy, you risk either leaving stale incorrect data in production or breaking dependent dashboards mid-analysis.

Backfilling matters most when: (1) you discover a calculation bug affecting months of data, (2) you add a new column or transformation rule retroactively, (3) your source system corrected historical records. The danger zone is partial backfills—running day 1 and day 3 but not day 2—which creates gaps. Equally risky is backfilling while incremental runs are still landing today's data, causing race conditions and overwrites.

Without a backfill-aware design, you either manually delete and re-insert (risky, manual), or you accumulate multiple versions of the same fact (bloats storage, breaks aggregations). The safe approach uses idempotent upserts, clear time partitioning, and backfill-specific flags in orchestration so you can pause dependent jobs during the rerun window.

## Practice

**Problem:** Your `job_postings_fact` table has three months of data. A bug in the `salary_year_avg` calculation was just discovered—you divided by 12 instead of 13 pay periods. You need to recalculate and safely replace those rows for Jan–Mar without breaking downstream reports that query this week's data.

```sql
-- Backfill approach: insert into temp table, then atomic swap or upsert
CREATE TABLE job_postings_fact_backfill AS
SELECT 
  job_id,
  job_title_short,
  ROUND(salary_raw / 13.0) AS salary_year_avg,  -- Fixed calculation
  job_work_from_home,
  job_posted_date,
  job_location,
  CURRENT_TIMESTAMP AS dbt_updated_at
FROM raw_job_postings
WHERE job_posted_date >= '2024-01-01' 
  AND job_posted_date < '2024-04-01'
  AND deleted_at IS NULL;

-- Option A: Merge/upsert if your DB supports it (Postgres, Snowflake, BigQuery)
MERGE INTO job_postings_fact AS target
USING job_postings_fact_backfill AS source
ON target.job_id = source.job_id
WHEN MATCHED THEN
  UPDATE SET 
    salary_year_avg = source.salary_year_avg,
    dbt_updated_at = source.dbt_updated_at
WHEN NOT MATCHED THEN
  INSERT *;

-- Option B: Delete and reinsert (safer for systems without MERGE)
DELETE FROM job_postings_fact 
WHERE job_posted_date >= '2024-01-01' AND job_posted_date < '2024-04-01';

INSERT INTO job_postings_fact
SELECT * FROM job_postings_fact_backfill;

DROP TABLE job_postings_fact_backfill;
```

## Notes

- **Idempotency is non-negotiable:** your backfill query must produce identical results if run twice on the same period, using `DELETE WHERE date_range` before insert, or MERGE with a primary key.
- **Partition pruning prevents accidents:** always filter by a date column in both source and target; backfilling all data when you meant Jan–Mar is career-limiting.
- **Pause or isolate downstream jobs:** use orchestration (Airflow, dbt Cloud, Prefect) to block dashboards or dependent models from running until backfill completes, or use a flag column to mark "backfilled" rows.
- **Version your backfill:** log which records changed and why (add a `backfill_reason` or `backfill_run_id` column) so you can audit and possibly reverse if needed.
- **Adjacent topics:** idempotency in general, table schemas and partitioning strategy, orchestration dependency graphs, data validation tests (compare backfilled vs. original using dbt tests or Great Expectations).
