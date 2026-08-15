---
date: 2026-08-15
phase: streaming
topic: Stream processing with Flink or Kafka Streams
---

# Stream processing with Flink or Kafka Streams

*Streaming and distributed processing*

## Concept

Stream processing frameworks like Apache Flink and Kafka Streams handle unbounded, out-of-order data by treating it as continuous flows rather than finite batches. Unlike traditional SQL databases that assume complete datasets, these systems ingest records one or many at a time, apply transformations, and emit results without waiting for all data to arrive. This is essential for real-time analytics: fraud detection cannot wait until end-of-day, nor can anomaly alerts in infrastructure monitoring.

The critical challenge is *time*. Records arrive out of order—a user action logged in New York may hit your Kafka topic after an action from Tokyo, despite occurring first. Without explicit windowing and watermarks, you cannot reliably aggregate or join streams. Additionally, state management becomes crucial: if you need to count events per user over a sliding window, you must maintain partial counts in memory and know when to close and emit a window, even if stragglers arrive later.

Without stream processing, you fall back to batch jobs running hourly or daily, missing actionable patterns. Dashboards become stale, operational decisions lag behind reality, and downstream systems have no way to react in the moment.

## Practice

**Problem:** Track the average salary by job location for postings created in the last hour, updating every 5 minutes. Remote positions (job_work_from_home = true) should be counted separately as "Remote." Handle late-arriving records up to 15 minutes after their posted_date.

```sql
SELECT
    CASE 
        WHEN job_work_from_home THEN 'Remote'
        ELSE job_location
    END AS location,
    COUNT(*) AS posting_count,
    ROUND(AVG(salary_year_avg), 2) AS avg_salary,
    TUMBLE_END(job_posted_date, INTERVAL '5' MINUTE) AS window_end
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY
    TUMBLE(job_posted_date, INTERVAL '5' MINUTE),
    CASE 
        WHEN job_work_from_home THEN 'Remote'
        ELSE job_location
    END
```

*(This assumes Flink SQL or Kafka Streams DSL; the TUMBLE window groups 5-minute intervals, and the WHERE clause on salary filters nulls. Watermark configuration on job_posted_date would permit 15-minute lateness.)*

## Notes

- **Watermark confusion:** A watermark signals "no events earlier than time X will arrive"; it doesn't drop late data but tells the engine when to close windows. Forgetting to define one means windows never fire.
- **Exactly-once semantics:** Kafka Streams and Flink both support exactly-once processing, but only if you use idempotent sinks or transactions; a naive Kafka producer can cause duplicates on failure.
- **State explosion:** Long-lived state (e.g., per-user aggregations over days) bloats memory; always scope windows and use TTL policies to evict stale state.
- **Joins in streams:** Stream-stream joins require maintaining both sides in state; stream-table (enrichment) joins pull from external stores and add latency—know which you need.
- **Adjacent topics:** CEP (Complex Event Processing) for multi-stage patterns; session windows for user behavior clustering; side outputs for handling late/erroneous records separately.
