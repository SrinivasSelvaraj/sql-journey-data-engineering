---
date: 2026-10-17
phase: streaming
topic: Throughput vs latency trade-off in streaming systems
---

# Throughput vs latency trade-off in streaming systems

*Streaming and distributed processing*

## Concept

In streaming systems, throughput (events processed per unit time) and latency (delay from event arrival to result availability) are inversely related. Higher throughput typically requires batching more events together, which increases latency; lower latency demands processing events individually or in tiny windows, which reduces throughput. The trade-off becomes acute when you have unpredictable arrival rates, network congestion, or resource constraints—you must choose whether to prioritize steady-state volume (throughput) or responsiveness (latency).

This matters whenever downstream decisions depend on fresh data: fraud detection needs low latency to block transactions in real-time, but billing pipelines can tolerate higher latency if they process millions of events reliably. Without understanding this trade-off, you build systems that either drop events under load (prioritizing latency incorrectly) or create backlogs that render alerts useless (prioritizing throughput incorrectly).

The tension forces concrete choices: micro-batching windows (Spark Streaming, Kafka), buffer sizes, checkpoint frequencies, and backpressure mechanisms all encode this decision into your architecture.

## Practice

**Problem:** A job posting stream arrives unpredictably with 10–1000 events/second. You need to emit alerts when median salary for a job title exceeds a threshold in the last hour, but alerts must arrive within 5 minutes of the triggering event. Design a solution that doesn't lose events or delay alerts excessively.

```sql
-- Low-latency, moderate-throughput approach: 
-- 5-minute tumbling windows with early results

CREATE TABLE job_postings_windowed AS
SELECT 
  TUMBLE_START(job_posted_date, INTERVAL '5' MINUTE) AS window_start,
  job_title_short,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) AS median_salary,
  COUNT(*) AS event_count
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY 
  TUMBLE(job_posted_date, INTERVAL '5' MINUTE),
  job_title_short;

-- Alert on first window closure, not when threshold is crossed mid-window
CREATE TABLE salary_alerts AS
SELECT 
  window_start,
  job_title_short,
  median_salary
FROM job_postings_windowed
WHERE median_salary > 120000
  AND event_count >= 10;  -- suppress noise from tiny samples
```

**Trade-off rationale:** 5-minute windows meet the 5-minute alert SLA while batching enough events to amortize network/compute costs. Tumbling (non-overlapping) windows maximize throughput vs. sliding windows. The `event_count` filter sacrifices some latency for reliability—wait for statistical significance rather than alert on noise.

## Notes

- **Common mistake:** Setting window size equal to your SLA (alert in 5 minutes → use 5-minute windows). Windows add latency *on top* of processing time; a 5-minute window emits results 5+ minutes after the first event, not 5 minutes after the last.
- **Backpressure and buffering:** Throughput optimization often silently drops events or grows unbounded queues. Always size buffers explicitly and fail loudly when full (reject) rather than silently delay.
- **Connects to:** Exactly-once semantics (idempotency absorbs duplicate retries at low latency), watermarking (distinguishing late data from system delay), and checkpoint alignment (latency cost of durability guarantees).
- **Revisit:** Adaptive windowing and dynamic SLAs—some systems adjust window size based on arrival rate to maintain target latency as load varies.
- **Measurement:** Profile both *end-to-end latency* (event ingestion to alert) and *processing latency* (batch start to result) separately; network and queue time often dominate.
