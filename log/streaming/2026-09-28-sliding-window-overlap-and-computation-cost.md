---
date: 2026-09-28
phase: streaming
topic: Sliding window overlap and computation cost
---

# Sliding window overlap and computation cost

*Streaming and distributed processing*

## Concept

Sliding windows in streaming contexts compute aggregates over time ranges that overlap—for example, "revenue in the last 7 days" recalculated every hour. Without understanding overlap, you either recompute everything from scratch (wasteful) or incorrectly cache results across windows (silent correctness bugs). The cost compounds because late-arriving data can invalidate windows you thought were closed, forcing re-aggregation of rows already processed.

In distributed systems, overlapping windows create a coordination problem: if window state lives in different partitions, late data arriving to one partition cannot update the aggregates in others. Most streaming engines (Flink, Spark Structured Streaming, Kafka Streams) handle this by either buffering late data up to a grace period, or by accepting incompleteness. Understanding the tradeoff between latency, completeness, and compute cost is essential for production systems.

The computation cost rises with window size, slide interval, and data volume. A 30-day sliding window with 1-hour slides on a billion-row-per-day stream is expensive if you recalculate from raw data each time. Incremental computation (adding new rows, removing old ones) is faster but requires stateful storage. Late-arriving data that falls into already-emitted windows forces you to either retract old results or accept approximate outputs.

## Practice

**Problem:** Calculate the average salary and count of remote jobs posted in each 7-day rolling window (sliding by 1 day), for the last 30 days of data. Identify which days' windows saw the most remote job postings.

```sql
WITH daily_remote_summary AS (
  SELECT
    job_posted_date,
    COUNT(*) AS job_count,
    AVG(salary_year_avg) AS avg_salary,
    SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) AS remote_count
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
  GROUP BY job_posted_date
),
sliding_window AS (
  SELECT
    window_start,
    window_end,
    SUM(remote_count) AS total_remote_jobs,
    SUM(job_count) AS total_jobs,
    AVG(avg_salary) AS avg_salary_in_window
  FROM daily_remote_summary
  CROSS JOIN LATERAL (
    SELECT
      job_posted_date AS window_start,
      DATE_ADD(job_posted_date, INTERVAL 6 DAY) AS window_end
  ) w
  WHERE daily_remote_summary.job_posted_date BETWEEN w.window_start AND w.window_end
  GROUP BY window_start, window_end
)
SELECT
  window_start,
  window_end,
  total_remote_jobs,
  ROUND(avg_salary_in_window, 2) AS avg_salary,
  ROW_NUMBER() OVER (ORDER BY total_remote_jobs DESC) AS rank_by_remote_count
FROM sliding_window
ORDER BY window_start;
```

## Notes

- **Incremental vs. full recompute:** Pre-aggregate by day (as above), then slide across summaries rather than raw rows. This cuts recomputation cost by orders of magnitude but requires mutable state.
- **Late data and retraction:** If a job posting with timestamp T arrives after its window has been output, you must either emit a retraction record (subtract old aggregate, emit new one) or accept that historical windows are final and gate out late arrivals.
- **State size and memory:** A 30-day window on a high-volume stream can require significant state. Bloom filters or HyperLogLog sketches reduce memory at the cost of approximate results.
- **Watermarks and grace periods:** Streaming engines use watermarks to signal "no more data before time X" and grace periods to allow late arrivals. Setting grace period too high delays output; too low silently drops important updates.
- **Connects to:** window triggers (when to emit), accumulation modes (discard vs. accumulate vs. retract), and state backend durability (RocksDB, etc.). Also relevant to session windows (event-driven, not time-driven) and suppression patterns (only emit on change).
