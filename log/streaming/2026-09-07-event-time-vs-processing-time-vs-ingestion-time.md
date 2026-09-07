---
date: 2026-09-07
phase: streaming
topic: Event time vs processing time vs ingestion time
---

# Event time vs processing time vs ingestion time

*Streaming and distributed processing*

## Concept

**Event time** is when something actually happened in the real world (e.g., a user clicked a button, a sensor recorded a reading). **Processing time** is when your system processes that event—which may be seconds, hours, or days later. **Ingestion time** sits between them: the timestamp assigned when data enters your pipeline, often used as a fallback when event time is unavailable or unreliable.

Event time matters because business logic depends on it. If you're calculating daily revenue, you need to know when purchases *actually occurred*, not when your batch job ran at 2 AM. Processing time is what you *can* measure easily, but it's unreliable for analysis—late-arriving data, system outages, and backpressure cause skew. Without distinguishing these, you'll build dashboards that mysteriously change when you reprocess old data, or miss fraud that happened hours ago but arrived late.

In practice: use event time for all metric calculations (windows, aggregations, joins). Use processing time only for monitoring pipeline health. Ingestion time is a rescue when event time is missing, but it's a compromise—you lose causality.

## Practice

**Problem:** Your job postings data arrives out of order. A job posted on 2025-01-15 might not arrive in your system until 2025-01-18, while jobs posted on 2025-01-16 already arrived. You need to calculate "jobs posted yesterday" for a daily report, but you're getting inconsistent counts depending on *when* you run the query. Design a solution.

```sql
-- Add event_time and processing_time to the schema
CREATE TABLE job_postings_fact (
  job_id STRING,
  job_title_short STRING,
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,           -- event time (when it was posted)
  job_location STRING,
  ingestion_timestamp TIMESTAMP,  -- when it entered the pipeline
  processing_timestamp TIMESTAMP  -- current query time
);

-- Correct: count jobs by event time, not arrival time
SELECT 
  job_posted_date,
  COUNT(*) as job_count
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE - 1
GROUP BY job_posted_date;

-- Wrong: this changes every time you run it if data arrives late
-- SELECT job_posted_date, COUNT(*) FROM job_postings_fact
-- WHERE ingestion_timestamp >= CURRENT_TIMESTAMP - 1 DAY

-- For late arrivals, use a watermark or allowed lateness window:
SELECT 
  job_posted_date,
  COUNT(*) as job_count,
  MAX(ingestion_timestamp) as latest_arrival
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 8  -- look back 1 week
  AND ingestion_timestamp < CURRENT_TIMESTAMP
GROUP BY job_posted_date
ORDER BY job_posted_date DESC;
```

## Notes

- **Common mistake:** confusing processing_time with event_time in window functions. `TUMBLE(CURRENT_TIMESTAMP, ...)` is wrong; use `TUMBLE(event_timestamp, ...)`.
- **Late data handling:** define a watermark (e.g., "allow 24 hours of late arrivals") so you can close windows and emit results without waiting forever.
- **Connects to:** windowing strategies (tumbling, sliding, session), exactly-once semantics, and idempotent writes—if you reprocess data, your counts must remain consistent.
- **Idempotency link:** event time makes reprocessing safe; processing time makes it a nightmare because you can't replay the same moment twice.
- **Revisit when:** debugging "why does my metric change after a day?" or designing retention policies—you need event time to know what's truly stale.
