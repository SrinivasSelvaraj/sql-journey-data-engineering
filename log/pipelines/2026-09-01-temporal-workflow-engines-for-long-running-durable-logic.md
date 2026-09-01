---
date: 2026-09-01
phase: pipelines
topic: Temporal: workflow engines for long-running durable logic
---

# Temporal: workflow engines for long-running durable logic

*Pipelines and orchestration*

## Concept

Temporal workflow engines (like Temporal, Airflow, Prefect) allow you to encode long-running, stateful business logic as code without managing retries, timeouts, and state persistence yourself. They capture the execution history and replay it deterministically, so a workflow can survive infrastructure failure and resume exactly where it left off. This matters when a job takes hours, calls external APIs, or spans multiple data systems—you cannot afford to lose progress or recompute from scratch.

Without a workflow engine, you either lose intermediate state (restart everything), manually checkpoint to a database (fragile and error-prone), or accept partial failures that corrupt downstream analytics. For example, if you scrape job postings, enrich them with salary data from an external service, and load them into a warehouse, and the service goes down during enrichment, you need to know which postings were already enriched, which are queued, and which failed—and restart only the failed ones without re-processing the rest.

Workflow engines solve this by making the execution log the source of truth. Each step produces an event (started, completed, failed), and the engine replays that log on recovery, so your code only runs once per task and always knows its own history.

## Practice

**Problem:** You receive a daily file of new job postings. You must validate the schema, deduplicate by job_id, enrich salaries from an external API (rate-limited to 10 req/sec), and then upsert into job_postings_fact. If the API is down or times out, you want to retry just the enrichment step without re-validating or re-deduplicating, and without losing which postings were already enriched today.

```sql
-- After workflow orchestration completes enrichment,
-- you upsert the enriched staging table into the fact table,
-- keyed on job_id and job_posted_date to handle late-arriving duplicates.

MERGE INTO job_postings_fact AS target
USING staging_enriched AS source
ON target.job_id = source.job_id 
   AND target.job_posted_date = source.job_posted_date
WHEN MATCHED THEN
  UPDATE SET 
    job_title_short = source.job_title_short,
    salary_year_avg = source.salary_year_avg,
    job_work_from_home = source.job_work_from_home,
    job_location = source.job_location
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, 
          source.job_work_from_home, source.job_posted_date, source.job_location);
```

The workflow engine handles retrying the enrichment step with exponential backoff; the SQL is idempotent and only runs once the enrichment is confirmed complete.

## Notes

- **Replay semantics:** Determinism is critical—if a task reads `NOW()` or rolls a random number, replay will give different results. Temporal workflows enforce this by injecting time; be aware of side effects outside your DAG.
- **Cost of durability:** Writing every event to a durable store has latency and storage overhead; suitable for pipelines with >5 minute tasks, not for microsecond-level streaming.
- **Airflow vs. Temporal:** Airflow is DAG-first and human-friendly for batch; Temporal is task-centric and better for long-running, async, human-in-the-loop workflows.
- **Checkpointing in SQL:** Use staging tables and transaction isolation (READ COMMITTED or REPEATABLE READ) to ensure upserts are idempotent when the workflow retries.
- **Observability:** Log every step's input, output, and duration into a metadata table; join with job_postings_fact on job_id to track which postings took longest to enrich or failed most often.
