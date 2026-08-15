---
date: 2026-08-15
phase: streaming
topic: Watermarks and late data handling
---

# Watermarks and late data handling

*Streaming and distributed processing*

## Concept

Watermarks are markers in streaming systems that define the boundary between on-time and late data. A watermark at time T asserts "no more data with event time ≤ T will arrive." Without watermarks, systems cannot decide when to close a window and emit results—you either emit prematurely (incomplete data) or wait forever (unbounded latency). Late data handling is the strategy for dealing with records that arrive after their watermark has passed: drop them, update previous results, or route them to a side output.

Watermarks matter in any unbounded stream where arrival time ≠ event time. Mobile apps, IoT sensors, and distributed logs routinely see data out of order by seconds to hours. A job posting platform tracking "salary posted today" must distinguish between records posted at 9am but arriving at 2pm (on-time, within the window) versus records posted yesterday that arrive today (late, potentially belonging to a closed window). Without explicit watermark logic, aggregate metrics like average salary per day become unreliable—you cannot know if you've seen all the day's data.

The cost of ignoring watermarks is silent data loss or correctness violations. A streaming job might emit total_postings_today=47 at midnight, then silently drop three records arriving at 12:05am. Or it might recompute the same aggregate multiple times, confusing downstream consumers. Watermark strategies (allowed lateness, session windows, custom triggers) force you to make that tradeoff explicit in code.

## Practice

**Problem:** You ingest job postings in real time and want to compute total salary budget (sum of salary_year_avg) per day, per location, closing each window at end-of-day. Postings occasionally arrive 2–3 hours late due to API delays. You need to emit preliminary results at midnight but also accept corrections for late postings.

```sql
-- Assuming a streaming table with event_time = job_posted_date, arrival_time = ingest timestamp
-- Using watermarking with allowed lateness (Flink SQL or similar)

CREATE TABLE job_postings_windowed AS
SELECT
  TUMBLE_START(job_posted_date, INTERVAL '1' DAY) AS window_start,
  job_location,
  SUM(salary_year_avg) AS total_salary_budget,
  COUNT(*) AS posting_count,
  MAX(CURRENT_TIMESTAMP) AS compute_time
FROM job_postings_fact
WHERE job_posted_date IS NOT NULL
GROUP BY
  TUMBLE(job_posted_date, INTERVAL '1' DAY),
  job_location;

-- Watermark definition (pseudo-config in application):
-- WATERMARK FOR job_posted_date AS job_posted_date - INTERVAL '3' HOUR
-- Meaning: data is expected within 3 hours; after that, treat as late.

-- For handling late data, emit to a correction topic:
INSERT INTO job_postings_corrections
SELECT
  job_posted_date,
  job_location,
  salary_year_avg,
  CURRENT_TIMESTAMP AS late_arrival_time
FROM job_postings_fact
WHERE CURRENT_TIMESTAMP - CAST(job_posted_date AS TIMESTAMP) > INTERVAL '3' HOUR;
```

## Notes

- **Watermark skew:** If one upstream partition stalls, the global watermark does not advance; all downstream computations block. Monitor watermark lag per partition.
- **Allowed lateness vs. drop:** Setting a high lateness window (e.g., 24 hours) trades cost (more state, multiple emits per key) for correctness. Know your SLA before choosing.
- **Event time vs. processing time:** Watermarks work on event time (job_posted_date), not the time a record arrived. Conflating these two is the #1 watermark mistake.
- **Retractions and side outputs:** Some frameworks emit retractions (undo old results) when late data arrives; others route late records to a side channel. Understand your framework's model.
- **Adjacent topics:** Session windows (dynamic boundaries), trigger strategies (custom emit conditions), and idempotent sinks (deduplication on corrections).
