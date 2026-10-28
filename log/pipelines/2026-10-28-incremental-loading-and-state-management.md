---
date: 2026-10-28
phase: pipelines
topic: Incremental loading and state management
---

# Incremental loading and state management

*Pipelines and orchestration*

## Concept

Incremental loading tracks which data has already been processed to avoid reprocessing the entire dataset on each pipeline run. Instead of extracting all historical records every time, you load only new or modified rows since the last successful execution. This is critical in production because full reloads become prohibitively expensive at scale—a job postings table growing by thousands of rows daily cannot be re-ingested completely each morning.

State management captures the "watermark" or checkpoint that marks where processing stopped. Common approaches include tracking the max date of processed records, using a dedicated state table, or leveraging source system change flags (created_at, updated_at). Without explicit state, you either duplicate data (processing the same row twice) or miss updates entirely. The state must survive pipeline failures—if your job crashes at 11:47 AM, you need to know you processed data only through 11:30 AM so the next run resumes from there, not from yesterday.

This pattern is foundational to building pipelines that "fail loudly, rerun safely." When state is managed correctly, a failed job can be retried without manual cleanup. When it's missing, retries cause data corruption, and recovery requires either rolling back the entire warehouse or manually deleting duplicates.

## Practice

**Problem:** Your job_postings_fact table receives 500–2000 new rows daily. Currently, the pipeline does a full truncate-and-reload every night, taking 6 minutes. As the source grows, this will become unworkable. Design an incremental load that captures only new postings since the last run.

```sql
-- State table: tracks the watermark for each source
CREATE TABLE IF NOT EXISTS pipeline_state (
  pipeline_name STRING,
  last_processed_date DATE,
  last_run_timestamp TIMESTAMP,
  PRIMARY KEY (pipeline_name)
);

-- On first run, initialize the state
INSERT INTO pipeline_state (pipeline_name, last_processed_date, last_run_timestamp)
VALUES ('job_postings_incremental', '2024-01-01', CURRENT_TIMESTAMP())
ON CONFLICT(pipeline_name) DO NOTHING;

-- Main incremental load: fetch only new rows
WITH state AS (
  SELECT last_processed_date FROM pipeline_state 
  WHERE pipeline_name = 'job_postings_incremental'
),
new_postings AS (
  SELECT 
    job_id, job_title_short, salary_year_avg, job_work_from_home, 
    job_posted_date, job_location
  FROM source_job_postings
  WHERE job_posted_date > (SELECT last_processed_date FROM state)
    AND job_posted_date <= CURRENT_DATE()
)
INSERT INTO job_postings_fact 
SELECT * FROM new_postings;

-- Update state after successful load (do this only after INSERT succeeds)
UPDATE pipeline_state
SET last_processed_date = CURRENT_DATE(),
    last_run_timestamp = CURRENT_TIMESTAMP()
WHERE pipeline_name = 'job_postings_incremental';
```

## Notes

- **State atomicity matters**: update the watermark *after* the data insert succeeds, not before. If you update state first and the insert fails, your next run will skip data.
- **Handle late-arriving data**: events may arrive out of order. Use a lookback window (e.g., `job_posted_date > last_processed_date - 2 days`) to catch corrections and updates.
- **Relates to idempotency**: pairing incremental loading with idempotent inserts (upserts on job_id) means retrying the same time window is safe; duplicates overwrite themselves.
- **Connect to orchestration**: tools like dbt, Airflow, and Prefect have built-in state/run context features—always use them rather than rolling your own timestamp logic.
- **Revisit for CDC**: as source systems grow, move beyond timestamp-based incremental to Change Data Capture (CDC) from database logs or Kafka for true delta awareness.
