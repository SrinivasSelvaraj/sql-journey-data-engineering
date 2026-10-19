---
date: 2026-10-19
phase: streaming
topic: Stream joins: stream-stream, stream-table, windowed joins
---

# Stream joins: stream-stream, stream-table, windowed joins

*Streaming and distributed processing*

## Concept

Stream joins combine data from two or more continuously arriving sources, matching records on a key. Unlike batch joins where both sides are complete, stream joins must decide: *when* to emit a result (before all data arrives), *what state* to keep in memory, and *how long* to wait for a late-arriving match. This is why windowed joins exist—they bound the wait time and memory footprint by only correlating events within a time interval.

Stream-stream joins (e.g., clicks matched with impressions) require both sides to buffer recent data; without a window, you'd wait forever for matches or run out of memory. Stream-table joins (e.g., enriching events with reference data) are simpler because the table is static—you just look up the latest value. Windowed joins (e.g., matching user actions within 10 minutes) explicitly close the correlation window, emitting results and clearing old state. Without clarity on windows, semantics, and state retention, you risk duplicate outputs, lost matches, or cascading memory leaks in production.

## Practice

**Problem:** You are ingesting a stream of job postings and a stream of job application events. You need to enrich each application with the job posting details (title, salary, location) at the moment the application arrived. Applications may arrive seconds or hours after the job was posted, but you want to capture the salary and location *as it was when the job was posted*, and you need to handle late applications up to 7 days after posting.

```sql
-- Assuming Kafka topics or similar: job_postings stream, applications stream
-- Using Flink SQL or Spark Structured Streaming syntax

SELECT 
  a.application_id,
  a.applicant_id,
  a.application_timestamp,
  j.job_id,
  j.job_title_short,
  j.salary_year_avg,
  j.job_location,
  j.job_work_from_home
FROM applications a
INNER JOIN job_postings_fact FOR SYSTEM_TIME AS OF a.application_timestamp AS j
  ON a.job_id = j.job_id
WHERE a.application_timestamp BETWEEN j.job_posted_date 
  AND j.job_posted_date + INTERVAL '7' DAY;

-- Alternative: explicit windowed join (Spark)
SELECT 
  a.application_id,
  a.applicant_id,
  j.job_id,
  j.job_title_short,
  j.salary_year_avg
FROM applications a
INNER JOIN job_postings j
  ON a.job_id = j.job_id
  AND a.application_timestamp BETWEEN j.job_posted_date 
    AND j.job_posted_date + INTERVAL 7 DAY
```

## Notes

- **Stateful bloat:** Unbounded stream-stream joins require holding every recent record from both streams; always define a window or use a lookup table (stream-table) instead to control memory.
- **Semantics matter:** Clarify whether you want inner/left/right/outer join; left join on a stream-stream can emit multiple times if the right side arrives late, causing duplicates downstream.
- **Watermarks and allowed lateness:** Set your watermark strategy and allowed lateness *before* joining; late data after the grace period is typically dropped or sent to a side output.
- **Stream-table vs. stream-stream:** If one side is reference data (jobs, users, rules), use a broadcast or versioned table join; reserve true stream-stream joins for correlated events only.
- **Adjacent: changelog streams, temporal joins, sessionization**—understand how to version and snapshot reference tables, and how session windows differ from tumbling/sliding windows for grouping.
