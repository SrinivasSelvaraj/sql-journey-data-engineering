---
date: 2026-10-13
phase: pipelines
topic: Exactly-once semantics: deduplication and idempotency
---

# Exactly-once semantics: deduplication and idempotency

*Pipelines and orchestration*

## Concept

Exactly-once semantics means each input record produces exactly one output record, even when operators fail and retry. Without it, duplicate ingestion, network retries, or failed task restarts can silently multiply rows—a $10M contract appears twice in revenue, a user gets billed thrice for one purchase. The problem compounds because duplicates often hide in logs until they affect downstream reports or trigger audit failures.

Two paths exist: **deduplication** (detect and remove duplicates after they arrive) and **idempotency** (design operations so re-executing them produces the same result). Idempotency is superior—it prevents duplicates from being created in the first place by keying writes on a unique identifier that remains stable across retries. Deduplication is a safety net when you cannot control the source system.

In practice, a streaming pipeline ingesting job postings might receive the same posting twice due to Kafka offset resets or source system retries. Without exactly-once, your fact table grows silently. With it, you either never insert the duplicate or you detect it, reject it, and log the incident loudly.

## Practice

**Problem:** A job posting is published, Kafka delivers it, your consumer crashes mid-insert. On restart, Kafka redelivers the same message from the last committed offset. How do you ensure `job_postings_fact` contains exactly one row per job posting, even across multiple failures?

```sql
-- Solution: Idempotent upsert using job_id as the natural key
-- Insert or update: if the job already exists, update only if source data changed
MERGE INTO job_postings_fact AS target
USING staging_job_postings AS source
  ON target.job_id = source.job_id
WHEN MATCHED AND (
  target.job_title_short != source.job_title_short
  OR target.salary_year_avg != source.salary_year_avg
  OR target.job_work_from_home != source.job_work_from_home
  OR target.job_location != source.job_location
)
  THEN UPDATE SET
    job_title_short = source.job_title_short,
    salary_year_avg = source.salary_year_avg,
    job_work_from_home = source.job_work_from_home,
    job_location = source.job_location,
    updated_at = CURRENT_TIMESTAMP
WHEN NOT MATCHED
  THEN INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location, created_at, updated_at)
    VALUES (source.job_id, source.job_title_short, source.salary_year_avg, source.job_work_from_home, source.job_posted_date, source.job_location, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
```

## Notes

- **Natural vs. surrogate keys:** Use a natural key (job_id) that comes from the source system, not a generated sequence. Sequences reset on failure and create duplicates; source keys are stable across retries.
- **Staging table pattern:** Land raw data in a staging table first, then merge idempotently into the fact table. This separates ingestion (which may retry) from deduplication (which runs once cleanly).
- **Exactly-once is not free:** It requires atomic operations (MERGE, upsert, transactions), deterministic source keys, and careful offset/transaction management. Stateless systems (pure maps, filters) are trivially exactly-once; stateful ones (aggregations, joins, writes) need explicit semantics.
- **Connects to:** transactional guarantees, offset management in streaming (Kafka committed offsets), distributed transaction patterns, and idempotent design in APIs.
- **Revisit when:** adding late-arriving data, handling out-of-order events, or moving between systems with different transactional guarantees (e.g., from a database with ACID to a data lake without).
