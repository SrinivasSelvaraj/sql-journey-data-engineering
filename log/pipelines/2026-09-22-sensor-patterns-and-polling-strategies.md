---
date: 2026-09-22
phase: pipelines
topic: Sensor patterns and polling strategies
---

# Sensor patterns and polling strategies

*Pipelines and orchestration*

## Concept

Sensor patterns and polling strategies determine how data pipelines detect new or changed data without constantly scanning entire datasets. A sensor is a mechanism that answers "is there work to do?" — it might check a file timestamp, query a high-water mark in a database, or monitor an external API. Polling is the act of repeatedly running that sensor on a schedule. This matters because naive approaches (full table scans on every run, or polling so frequently you waste compute) create runaway costs and brittle pipelines. Without thoughtful sensors, you either miss incremental data or reprocess everything, and when a pipeline fails midway through a poll cycle, you lose track of what you've already seen.

The core trade-off is latency vs. efficiency. High-frequency polling catches new data quickly but taxes your source system and storage. Low-frequency polling reduces load but delays insights. Effective sensor design uses markers — timestamps, sequence IDs, or file hashes — to answer "what changed since I last looked?" so your pipeline processes only deltas. This is where orchestration tools (Airflow, dbt Cloud) shine: they store sensor state and retry logic, letting you encode "run once per hour but skip if no new files arrived" as a declarative rule rather than custom code.

## Practice

**Problem:** Your `job_postings_fact` table receives new job postings throughout the day. You want a daily pipeline that loads only *new* postings since the last successful run, but you need to handle late-arriving data (posts backdated or corrected within 48 hours) and failed runs (restart without reloading yesterday's data).

```sql
-- Create a high-water mark table to track the last successful poll
CREATE TABLE pipeline_sensors (
  pipeline_name VARCHAR,
  last_successful_poll TIMESTAMP,
  rows_loaded INT,
  updated_at TIMESTAMP,
  PRIMARY KEY (pipeline_name)
);

-- Sensor query: identify the window of data to load
SELECT 
  MAX(job_posted_date) as cutoff_date,
  COUNT(*) as new_row_count
FROM job_postings_fact
WHERE job_posted_date > (
  SELECT COALESCE(last_successful_poll, '1900-01-01'::TIMESTAMP)
  FROM pipeline_sensors
  WHERE pipeline_name = 'daily_job_postings'
)
  AND job_posted_date <= CURRENT_DATE;

-- After successful load, update the sensor
UPDATE pipeline_sensors
SET 
  last_successful_poll = CURRENT_DATE,
  rows_loaded = (SELECT COUNT(*) FROM job_postings_fact 
                 WHERE job_posted_date = CURRENT_DATE),
  updated_at = NOW()
WHERE pipeline_name = 'daily_job_postings';

-- For late-arriving data, add a grace period to your sensor query
WHERE job_posted_date > (
  SELECT COALESCE(last_successful_poll, '1900-01-01'::TIMESTAMP) - INTERVAL '2 days'
  FROM pipeline_sensors
  WHERE pipeline_name = 'daily_job_postings'
)
```

## Notes

- **Idempotency is non-negotiable:** Sensors alone don't prevent duplicates if a pipeline reruns. Pair them with upsert logic (merge on `job_id`) so a retry is safe. The sensor tells you *what* to load; idempotent operations tell you it's safe to load it again.

- **State lives outside the code:** Store `last_successful_poll` in a durable table or external system (not environment variables or pipeline logs). On failure, the next run can query the real marker, not guess what "last time" was.

- **Late-arriving data requires grace periods:** Real-world data often arrives out-of-order. A 48-hour lookback window in your sensor query catches corrections and backdated entries; orchestration retry logic prevents duplicates.

- **Monitor the sensor itself:** A broken sensor (stuck timestamp, unresponsive API) silently skips data. Log sensor results (`row_count`, `cutoff_date`) to your observability stack so you catch "no new data for 7 days" anomalies early.

- **Connects to:** data quality gates (validate row counts before marking success), slowly changing dimensions (sensors for SCD Type 2 tables), and backfill strategies (manual sensor reset when you need to reprocess historical windows).
