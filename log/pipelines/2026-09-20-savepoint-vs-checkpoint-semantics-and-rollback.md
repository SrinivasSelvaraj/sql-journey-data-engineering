---
date: 2026-09-20
phase: pipelines
topic: Savepoint vs checkpoint semantics and rollback
---

# Savepoint vs checkpoint semantics and rollback

*Pipelines and orchestration*

## Concept

A **savepoint** is a named marker within a transaction that lets you rollback only to that point, keeping earlier work intact. A **checkpoint** is a durable snapshot of pipeline state written to external storage (files, tables, object stores) outside any transaction. Savepoints are SQL constructs; checkpoints are orchestration patterns.

Savepoints matter when a long transaction has multiple stages and you want partial recovery—commit the first stage, hit an error in stage two, roll back only stage two's work, then retry or skip it. Checkpoints matter in distributed pipelines where no single transaction spans all tasks; they ensure that if worker N fails, worker N+1 doesn't re-process already-completed work from workers 1 through N-1.

Without savepoints, one failed INSERT in a multi-step transaction rolls back everything. Without checkpoints, a failed Spark job that took 3 hours to load data will re-load from the source on retry—wasting compute and potentially hitting rate limits. Savepoints give you transaction-level granularity; checkpoints give you job-level resumability.

## Practice

**Problem:** You're building a nightly job that cleans job_postings_fact (remove nulls, deduplicate, validate dates), then enriches it (add region from location), then loads it to the warehouse. The dedupe step occasionally fails on bad data. You want to commit the cleaned data even if enrichment fails, so the next run resumes from enrichment, not from scratch.

```sql
BEGIN TRANSACTION;

-- Stage 1: Clean
DELETE FROM job_postings_fact WHERE salary_year_avg IS NULL OR job_posted_date IS NULL;
INSERT INTO job_postings_fact_cleaned 
  SELECT DISTINCT * FROM job_postings_fact;
SAVEPOINT after_clean;

-- Stage 2: Enrich (risky)
BEGIN
  UPDATE job_postings_fact_cleaned 
    SET job_location = CONCAT(job_location, ' - ', region_lookup.region)
    FROM region_lookup WHERE ...;
  SAVEPOINT after_enrich;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK TO SAVEPOINT after_clean;
  -- Commit only cleaned data; log error; next run will retry enrichment
  COMMIT;
  RAISE;
END;

COMMIT;
```

In orchestration (Airflow/dbt), write cleaned data to `job_postings_fact_cleaned` table and enrich into `job_postings_fact_enriched`. If enrichment fails, the next DAG run checks for existence of the cleaned table (checkpoint) and skips to the enrichment task—no re-cleaning.

## Notes

- **Savepoint ≠ checkpoint:** savepoints are transactional and in-memory; checkpoints are persistent and cross-process. Use savepoints for multi-stage SQL scripts; use checkpoints for multi-task pipelines.
- **Common mistake:** Treating checkpoints as transactions—if you write a checkpoint then the next transformation crashes before reading it, the checkpoint is orphaned and wastes storage. Always couple checkpoints with idempotent downstream logic.
- **Rollback scope matters:** rolling back to a savepoint inside a transaction doesn't release locks; the transaction is still open. For long pipelines, prefer committing after each stage and using checkpoints rather than one giant transaction with nested savepoints.
- **Adjacent pattern—idempotency:** checkpoints only work reliably if your downstream logic is idempotent (can re-run on the same checkpoint without duplicates). Foreign key constraints and upsert logic are your friends here.
- **Revisit:** interaction with distributed engines (Spark, Flink) where distributed transactions are expensive; how orchestrators like Airflow implement checkpoint semantics via XComs and task dependencies.
