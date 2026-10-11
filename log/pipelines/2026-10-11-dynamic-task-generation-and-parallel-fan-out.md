---
date: 2026-10-11
phase: pipelines
topic: Dynamic task generation and parallel fan-out
---

# Dynamic task generation and parallel fan-out

*Pipelines and orchestration*

## Concept

Dynamic task generation creates pipeline tasks at runtime based on data, rather than hardcoding them upfront. Fan-out then parallelizes those tasks across workers. Together they let you scale horizontally: process 10 files or 10,000 without rewriting the DAG.

The problem: static pipelines assume you know the work shape in advance. When you ingest 500 new data sources, onboard 50 new clients, or partition a table 20 ways, you either hardcode 500 tasks (unmaintainable) or rerun a single task sequentially (slow). Dynamic generation maps discovery → task spawn at runtime; fan-out ensures they execute in parallel.

Without this, you lose elasticity. The pipeline stalls on sequential processing, orchestrator memory bloats from thousands of hardcoded tasks, and DAG changes require code deploys. When it works, you write one templated task and it scales to your data volume automatically.

## Practice

**Problem:** Ingest job postings from multiple job boards (LinkedIn, Indeed, Glassdoor, etc.). Each board publishes files to a different S3 prefix daily. You need to detect all active prefixes, spawn an ingestion task per board, run them in parallel, then merge results into `job_postings_fact`.

**Solution:**

```sql
-- Step 1: Discovery query — which boards have new files today?
-- (Run this in orchestrator as a sensor/task to list S3 prefixes)
SELECT 
  SPLIT_PART(s3_key, '/', 2) AS board_name,
  COUNT(*) AS file_count,
  MAX(last_modified) AS latest_file
FROM s3_inventory
WHERE s3_key LIKE 's3://jobs-raw/%/2024-12-19/%'
GROUP BY board_name
HAVING COUNT(*) > 0;

-- Step 2: For each row above, dynamically spawn a task that runs:
-- INSERT INTO job_postings_fact
-- SELECT 
--   generate_uuid() AS job_id,
--   json_extract_scalar(raw_json, '$.title') AS job_title_short,
--   CAST(json_extract_scalar(raw_json, '$.salary') AS INT) AS salary_year_avg,
--   CAST(json_extract_scalar(raw_json, '$.remote') AS BOOLEAN) AS job_work_from_home,
--   CAST(json_extract_scalar(raw_json, '$.posted_date') AS DATE) AS job_posted_date,
--   json_extract_scalar(raw_json, '$.location') AS job_location
-- FROM s3://jobs-raw/{board_name}/2024-12-19/*
-- WHERE _file_name NOT IN (SELECT source_file FROM job_postings_fact WHERE source_board = '{board_name}')

-- Step 3: Merge task runs after all fan-out tasks complete
-- (idempotent; dedup by job_id or (board_name, source_id) pair)
DELETE FROM job_postings_fact 
WHERE job_posted_date = '2024-12-19';

INSERT INTO job_postings_fact
SELECT DISTINCT * FROM job_postings_staging;
```

## Notes

- **Task templating is key:** write one parameterized task (board_name = {param}) and let the orchestrator substitute it per discovered partition. Airbnb's DynamicTaskGroup and dbt's `parse_list` do this elegantly.
- **Idempotency or exactly-once:** fan-out tasks may retry. Either make inserts idempotent (upsert by natural key) or use staging tables + final merge, not direct writes.
- **Discovery overhead:** querying S3 inventory or metadata can itself be expensive. Cache the manifest or use event-driven triggers (S3 events → SNS → queue) to avoid scanning million-object buckets daily.
- **Observability gaps:** dynamic tasks are harder to trace. Log task_id, board_name, and file count in each spawned task. Alert on zero tasks spawned (silent failure).
- **Related:** backfill patterns (time-windowed fan-out over date ranges), partition elimination (only generate tasks for changed partitions), incremental materialization (fan-out by table, not file).
