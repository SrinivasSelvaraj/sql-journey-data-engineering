---
date: 2026-08-15
phase: streaming
topic: Windowing: tumbling, sliding, session
---

# Windowing: tumbling, sliding, session

*Streaming and distributed processing*

## Concept

Windowing partitions unbounded streams into finite, analyzable chunks so you can compute aggregates on data that never stops arriving. Without windows, an aggregation query on a stream has no natural stopping point—`SELECT COUNT(*) FROM events` would hang forever waiting for all events. The three main strategies differ in how they define boundaries: **tumbling windows** divide time into fixed, non-overlapping intervals (e.g., 1-hour buckets); **sliding windows** overlap and move at a fixed step (e.g., 5-minute windows that advance every 1 minute), capturing trends; **session windows** are event-driven and close after a period of inactivity, making them ideal for user behavior analysis where a "session" is the natural unit.

Choice of window type directly affects latency, completeness, and cost. Tumbling windows are cheap and clean—each event belongs to exactly one window—but you lose intermediate state. Sliding windows multiply computation (each event touches multiple windows) but reveal trends missed by tumbling. Session windows handle irregular traffic elegantly but require state to track idle periods, and they cannot emit results until the inactivity threshold is certain, introducing latency.

Streaming systems (Flink, Spark Structured Streaming, Kafka Streams) require you to declare windows explicitly in your query. Miss this step and you either get an error (if the system enforces it) or an incorrect full-stream aggregate. Time must also be defined: event time (when the data was generated) vs. processing time (when it arrived at your system). Event time is almost always correct for business logic, but requires handling late-arriving and out-of-order data.

## Practice

**Problem:** You have a stream of job postings. Compute the average salary per job title for each hour, then separately compute a 7-day rolling average. Also identify session windows of job postings from the same location (inactivity gap ≥ 6 hours).

```sql
-- Tumbling window: 1-hour non-overlapping buckets
SELECT
  TUMBLE_START(job_posted_date, INTERVAL '1' HOUR) AS window_start,
  job_title_short,
  AVG(salary_year_avg) AS avg_salary_hourly,
  COUNT(*) AS posting_count
FROM job_postings_fact
GROUP BY TUMBLE(job_posted_date, INTERVAL '1' HOUR), job_title_short;

-- Sliding window: 7-day rolling average, advancing every 1 day
SELECT
  HOP_START(job_posted_date, INTERVAL '1' DAY, INTERVAL '7' DAY) AS window_start,
  job_title_short,
  AVG(salary_year_avg) AS avg_salary_7day_rolling
FROM job_postings_fact
GROUP BY HOP(job_posted_date, INTERVAL '1' DAY, INTERVAL '7' DAY), job_title_short;

-- Session window: close after 6 hours of no postings from same location
SELECT
  SESSION_START(job_posted_date, INTERVAL '6' HOUR) AS session_start,
  SESSION_END(job_posted_date, INTERVAL '6' HOUR) AS session_end,
  job_location,
  COUNT(*) AS postings_in_session,
  AVG(salary_year_avg) AS avg_salary_per_session
FROM job_postings_fact
GROUP BY SESSION(job_posted_date, INTERVAL '6' HOUR), job_location;
```

## Notes

- **Common mistake:** confusing event time with processing time; using processing time (when the row arrived) breaks repeatability and produces different results on replay. Always use event time (`job_posted_date`) for business logic.
- **Allowed lateness:** set a grace period so late-arriving rows can still update closed windows. Too strict and you lose data; too loose and you hold state forever.
- **State management:** session and sliding windows require the system to hold state (open windows, idle timers). Monitor state size; large windows with high cardinality keys can cause memory issues or backpressure.
- **Watermarking:** use watermarks to signal "no more data before this time will arrive"—this lets the system safely close windows and emit results, reducing latency.
- **Related:** understand trigger semantics (when to emit results: on event arrival, on window close, on timer); watermark propagation in multi-stage pipelines; and how late data interacts with retraction/updates in stateful joins.
