---
date: 2026-09-08
phase: streaming
topic: Sink connectors: exactly-once writes to external stores
---

# Sink connectors: exactly-once writes to external stores

*Streaming and distributed processing*

## Concept

Exactly-once writes mean that each record from a streaming source is written to an external store exactly once, despite network failures, process crashes, or duplicate delivery from upstream. Without this guarantee, you risk duplicate rows in your data warehouse or payment systems processing the same transaction twice. This is harder than exactly-once *reads* because you must coordinate between the streaming framework (which may replay messages) and the sink system (which may not know about previous writes).

The core challenge: streaming systems naturally replay data on failure, but external stores have no memory of partial writes. If a sink connector writes 500 rows then crashes before committing the transaction, restarting will either skip those rows (losing data) or write them again (duplicates). Exactly-once requires idempotent writes or distributed transactions that tie success to the stream's offset commit.

In practice, this matters most for financial systems, inventory updates, and fact tables where duplicates compound. A CDC pipeline writing to a data warehouse via Kafka and Flink must ensure each changed row lands exactly once in the target table, not twice on worker failure.

## Practice

**Problem:** A real-time job posting pipeline ingests 50,000 postings per day into Kafka. You build a Flink sink that writes to a PostgreSQL `job_postings_fact` table. During high load, your Flink task manager crashes after writing 1,200 rows but before committing. On restart, Kafka replays those 1,200 messages. How do you prevent duplicate job_postings_fact rows?

```sql
-- Solution: Use an upsert/merge with a unique constraint and idempotent key
-- 1. Add a unique constraint on job_id (or job_id + job_posted_date for multiple postings per job)
ALTER TABLE job_postings_fact 
ADD CONSTRAINT uk_job_id UNIQUE(job_id);

-- 2. Configure Flink sink with upsert mode (or use MERGE in Postgres 15+)
-- Pseudo-config for Flink JDBC sink:
-- - setUpsertMode(true)
-- - setPrimaryKey(["job_id"])
-- - SQL operation becomes: INSERT ... ON CONFLICT(job_id) DO UPDATE SET ...

-- 3. The actual Flink sink logic (conceptual):
-- INSERT INTO job_postings_fact 
--   (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
-- VALUES (?, ?, ?, ?, ?, ?)
-- ON CONFLICT (job_id) DO UPDATE SET 
--   job_title_short = EXCLUDED.job_title_short,
--   salary_year_avg = EXCLUDED.salary_year_avg,
--   job_work_from_home = EXCLUDED.job_work_from_home,
--   job_posted_date = EXCLUDED.job_posted_date,
--   job_location = EXCLUDED.job_location;

-- Replayed writes with same job_id will overwrite, not duplicate
SELECT COUNT(*) FROM job_postings_fact WHERE job_posted_date = CURRENT_DATE;
```

## Notes

- **Idempotence vs. transactions:** Idempotent sinks (upsert on unique key) are simpler than distributed 2-phase commit but require your sink to tolerate rewrites; they work well for fact tables and dimensional updates.
- **Offset commit timing:** Only commit the Kafka offset *after* the external write succeeds and is durable, not before. Committing early loses data on failure; committing late causes replays.
- **Exactly-once vs. at-least-once:** At-least-once is cheaper (no coordination overhead) but requires downstream deduplication; exactly-once pushes complexity into the sink itself.
- **Connector choice matters:** Flink's JDBC sink with upsert mode handles this well; Kafka Connect sinks vary wildly—some guarantee exactly-once (Postgres, BigQuery), others only at-least-once (generic HTTP).
- **Related:** Understand idempotent keys, Flink's CheckpointedFunction for state management, and how CDC tools (Debezium) layer exactly-once semantics on top of Kafka.
