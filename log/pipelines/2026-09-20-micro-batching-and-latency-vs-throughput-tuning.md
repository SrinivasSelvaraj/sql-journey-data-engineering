---
date: 2026-09-20
phase: pipelines
topic: Micro-batching and latency vs throughput tuning
---

# Micro-batching and latency vs throughput tuning

*Pipelines and orchestration*

## Concept

Micro-batching groups streaming data into small time-windowed or size-windowed batches rather than processing every record individually. This is the bridge between true streaming (high latency, lower throughput) and batch processing (low latency potential, higher throughput). Spark Structured Streaming, Flink, and Kafka Streams all use micro-batching or similar approaches to balance resource efficiency against end-to-end latency.

Latency tuning shrinks the window (process more frequently), but increases overhead—more task scheduling, more state snapshots, more checkpoints written to disk. Throughput tuning widens the window (accumulate more records per batch), reducing overhead per record but delaying visibility into results. The trade-off surfaces most painfully in fraud detection (need sub-second latency), real-time dashboards (minutes are acceptable), and cost-optimized ETL (hours are fine).

Without intentional tuning, you either accumulate unbounded memory (records pile up), miss SLAs (batch windows too wide), or waste compute (windows too narrow, checkpoint overhead dominates). Monitoring end-to-end latency percentiles, scheduling lag, and checkpoint duration reveals which knob to turn.

## Practice

**Problem:** Ingest job postings daily; detect posting surges (>500 posts in a rolling 5-minute window) to alert hiring teams in near real-time. Current setup micro-batches every 30 seconds but causes CPU spikes from frequent checkpoints. You need to reduce overhead while staying under 2-minute detection latency.

```sql
-- Micro-batch ingestion with configurable window + grace period
-- Tuning: increase micro-batch interval from 30s to 60s, 
-- and allow 1-min late arrival grace to reduce state churn

WITH micro_batches AS (
  SELECT 
    DATE_TRUNC('minute', job_posted_date) AS batch_window,
    COUNT(*) AS posting_count,
    APPROX_PERCENTILE_CONT(salary_year_avg, 0.5) AS median_salary,
    SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) AS remote_count
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_TIMESTAMP - INTERVAL 6 MINUTES
  GROUP BY 1
),
surge_detection AS (
  SELECT 
    batch_window,
    posting_count,
    SUM(posting_count) OVER (
      ORDER BY batch_window 
      ROWS BETWEEN 4 PRECEDING AND CURRENT ROW
    ) AS rolling_5min_count
  FROM micro_batches
)
SELECT 
  batch_window,
  posting_count,
  rolling_5min_count,
  CASE WHEN rolling_5min_count > 500 THEN 'SURGE_ALERT' ELSE 'NORMAL' END AS alert_status
FROM surge_detection
WHERE rolling_5min_count > 500
ORDER BY batch_window DESC;
```

## Notes

- **Checkpoint tuning matters more than window size:** A 60-second window with lightweight checkpoints often outperforms a 10-second window with full state snapshots. Profile checkpoint write time, not just batch duration.
- **Watermarks and allowed lateness prevent data loss:** Set grace periods (allowed late-arrival windows) slightly longer than network jitter + upstream SLA; wider grace = more state overhead, narrower grace = dropped records. Balance explicitly.
- **Micro-batching hides backpressure problems:** Unlike true streaming, your buffer can silently grow if batches fall behind. Monitor queue depth and lag, not just throughput.
- **Adjacent: Exactly-once semantics and idempotency** — micro-batch windows are only safe if your downstream accepts duplicate writes or your pipeline is idempotent; checkpoint state alone does not guarantee end-to-end correctness.
- **Revisit when:** SLA changes, data volume doubles, or new low-latency use case emerges (e.g., fraud → surge detection). Rerun latency percentiles (p50, p95, p99) quarterly.
