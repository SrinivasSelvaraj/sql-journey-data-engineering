---
date: 2026-09-05
phase: streaming
topic: Spark Structured Streaming: micro-batch vs continuous
---

# Spark Structured Streaming: micro-batch vs continuous

*Streaming and distributed processing*

## Concept

Spark Structured Streaming offers two execution modes that fundamentally differ in latency-throughput tradeoffs. **Micro-batch mode** (default) collects arriving data into small batches processed every interval (e.g., 500ms); each batch is a DataFrame triggering a single Spark job. **Continuous mode** (experimental) processes data with sub-100ms latency by running a single long-lived job that reads and writes continuously without batching boundaries. Micro-batch is deterministic and fault-tolerant by design—each batch commits independently, making recovery straightforward. Continuous mode trades some guarantees for lower latency, better suited for high-frequency alerting or live dashboards.

When you ingest job postings in real time, micro-batch lets you reliably aggregate salary trends every 30 seconds; continuous mode lets you push individual posting alerts to users within milliseconds. Without understanding this distinction, you risk over-engineering for latency you don't need (continuous complexity) or accepting unacceptable delays in low-latency use cases. The choice also affects stateful operations: micro-batch handles windowing and deduplication predictably; continuous mode requires more careful state management and offers no built-in exactly-once guarantee outside certain sinks.

## Practice

**Problem:** Ingest a stream of job postings and compute a rolling 5-minute count of remote work-from-home positions by job title, updating every 30 seconds. You must not double-count duplicates and must tolerate late arrivals up to 2 minutes.

```sql
SELECT 
  window(job_posted_date, '5 minutes', '30 seconds') as time_window,
  job_title_short,
  COUNT(DISTINCT job_id) as remote_job_count
FROM job_postings_fact
WHERE job_work_from_home = true
  AND job_posted_date > current_timestamp() - INTERVAL 7 MINUTES
GROUP BY 
  window(job_posted_date, '5 minutes', '30 seconds'),
  job_title_short
ORDER BY time_window DESC, remote_job_count DESC
```

*Implementation note:* In PySpark, use `readStream().load()` with micro-batch mode (trigger every 30 seconds), apply `watermark("job_posted_date", "2 minutes")` to handle late data, and write to a sink (Kafka, Delta) with checkpoint directory to guarantee recovery and deduplication.

## Notes

- **Common mistake:** Confusing trigger interval with window duration. A 30-second trigger does not mean your window is 30 seconds; you must specify window and trigger independently.
- **Fault tolerance:** Micro-batch checkpoints after each batch; continuous mode checkpoints at epoch boundaries. Always enable checkpointing in production—without it, restarts lose state.
- **Exactly-once semantics:** Micro-batch guarantees exactly-once with idempotent sinks (Delta, JDBC with unique keys); continuous mode only guarantees exactly-once to certain sinks (Kafka). Verify your sink supports your mode.
- **State store overhead:** Windowing and joins in both modes require Spark to maintain state (RocksDB by default). Large state stores or many unique keys degrade performance; consider TTL and state pruning.
- **Related topics:** Watermarking (handling late data), event time vs. processing time, stateful operations (joins, aggregations), and sink idempotency are all tightly coupled to mode choice.
