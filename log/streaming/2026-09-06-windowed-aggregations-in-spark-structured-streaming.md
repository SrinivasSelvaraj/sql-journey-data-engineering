---
date: 2026-09-06
phase: streaming
topic: Windowed aggregations in Spark Structured Streaming
---

# Windowed aggregations in Spark Structured Streaming

*Streaming and distributed processing*

## Concept

Windowed aggregations in Spark Structured Streaming divide infinite data streams into fixed or sliding time buckets, allowing you to compute aggregates (count, sum, avg) over specific time periods rather than globally. Without windowing, aggregations would accumulate across all historical data, making it impossible to detect trends, anomalies, or answer questions like "how many jobs posted in the last hour?"

Windowed aggregations matter because streaming data arrives out-of-order and late. A timestamp from 2 hours ago might arrive now. Spark's watermarking mechanism tracks how long to wait for late data before closing a window; this trade-off between completeness and latency is fundamental to real-time systems. Without windowing, you either block indefinitely waiting for all data or lose late-arriving records.

Breakage occurs when you forget to include the time column in your groupBy, attempt aggregations without a watermark (causing unbounded state growth), or set watermarks too aggressively (discarding legitimately late data). Windowing forces you to be explicit about time semantics, which is why it's non-negotiable in production streaming pipelines.

## Practice

**Problem:** You have a stream of job postings and need to calculate the average salary posted per 10-minute window, only for remote jobs, and allow data up to 5 minutes late.

```sql
SELECT
  window(job_posted_date, '10 minutes', '5 minutes') AS time_window,
  COUNT(*) AS job_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM job_postings_fact
WHERE job_work_from_home = true
GROUP BY window(job_posted_date, '10 minutes', '5 minutes')
HAVING COUNT(*) > 0
ORDER BY time_window DESC
```

Or in PySpark with watermark:
```python
df.withWatermark("job_posted_date", "5 minutes") \
  .filter(col("job_work_from_home") == True) \
  .groupBy(window("job_posted_date", "10 minutes", "5 minutes")) \
  .agg(
    count("*").alias("job_count"),
    round(avg("salary_year_avg"), 2).alias("avg_salary")
  ) \
  .orderBy(desc("window"))
```

## Notes

- **Watermark must precede groupBy:** Always apply `withWatermark()` before aggregation on the timestamp column, or late data silently drops without error.
- **Tumbling vs. sliding windows:** Tumbling (no third parameter) partitions time into non-overlapping buckets; sliding windows overlap and generate more output—choose based on whether you need trend sensitivity.
- **State management cost:** Every open window consumes driver memory. Large numbers of keys or long watermarks multiplied across partitions can cause OOM; monitor `numStateRows` and `stateMemory` metrics.
- **Timestamp column matters:** Use event time (when data was created), not processing time (when Spark received it), to handle out-of-order arrival and replay scenarios correctly.
- **Adjacent:** Connect to session windows (close when gap > threshold), stateful operations, and Kafka offset management—understanding where your watermark value comes from is essential for end-to-end correctness.
