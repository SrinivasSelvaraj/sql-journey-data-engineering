---
date: 2026-11-02
phase: streaming
topic: Micro-batching vs true streaming tradeoffs
---

# Micro-batching vs true streaming tradeoffs

*Streaming and distributed processing*

## Concept

Micro-batching (Spark Streaming, Kafka → batch every N seconds) processes data in small fixed windows, while true streaming (Flink, Kafka Streams) processes events individually as they arrive. Micro-batching adds latency proportional to batch interval—a 5-second micro-batch guarantees 5+ seconds delay—but simplifies state management, exactly-once semantics, and resource scheduling. True streaming minimizes latency (sub-second) and reacts immediately to data arrival patterns, but demands more sophisticated fault tolerance and state backend complexity.

Choose micro-batching when you can tolerate minutes of latency (dashboards updated every 5 min, hourly aggregations), when you need strong consistency guarantees out of the box, or when your infrastructure is batch-oriented (Spark clusters, data warehouses). True streaming is necessary for alerting on anomalies within seconds, fraud detection, or systems where order and timing of individual events drive decisions. The tradeoff breaks down when you need *both* sub-second latency *and* complex joins against large state—you pay the cost of true streaming without the simplicity of batching.

## Practice

**Problem:** Job postings stream in continuously with late arrivals (postings appear 1–2 days after `job_posted_date`). You need to:
- Alert when salary jumps >20% within a 1-hour window for the same role+location
- Update a dashboard with rolling 1-hour salary stats every 5 minutes
- Exactly-once guarantee (no duplicate alerts)

For the dashboard (micro-batching is fine), use this approach:

```sql
-- Micro-batch: 5-minute tumbling window (Spark Structured Streaming)
SELECT 
  window(job_posted_date, '5 minutes') as window_time,
  job_title_short,
  job_location,
  COUNT(*) as posting_count,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as median_salary,
  MAX(salary_year_avg) - MIN(salary_year_avg) as salary_range
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY window(job_posted_date, '5 minutes'), job_title_short, job_location
```

For the alert (true streaming needed for sub-minute response):

```sql
-- True streaming: 1-hour sliding window with state (Flink/Kafka Streams pseudocode)
SELECT 
  job_title_short,
  job_location,
  MAX(salary_year_avg) OVER (
    PARTITION BY job_title_short, job_location 
    ORDER BY job_posted_date 
    RANGE BETWEEN INTERVAL '1' HOUR PRECEDING AND CURRENT ROW
  ) as max_salary_1h,
  LAG(MAX(salary_year_avg)) OVER (
    PARTITION BY job_title_short, job_location 
    ORDER BY job_posted_date 
    RANGE BETWEEN INTERVAL '2' HOUR PRECEDING AND INTERVAL '1' HOUR PRECEDING
  ) as prev_max_salary
FROM job_postings_fact
WHERE (MAX(salary_year_avg) / NULLIF(LAG(MAX(salary_year_avg)), 0) - 1) > 0.20
-- Emit alert immediately on match
```

## Notes

- **Latency illusion:** A 5-second micro-batch doesn't mean 5 seconds end-to-end; add scheduling overhead, processing time, and downstream sinks—expect 8–15s real latency.
- **State bloat in true streaming:** Holding 1-hour windows of job postings in RocksDB or similar requires careful TTL and compaction; micro-batching avoids this by discarding state after each batch.
- **Exactly-once vs at-least-once:** Micro-batching achieves exactly-once more naturally (idempotent batch writes); true streaming requires deduplication logic or transactional sinks, adding complexity.
- **Watermarking and late data:** Both need strategies for late arrivals (allowed lateness windows, side outputs); true streaming forces you to decide upfront, micro-batching can defer via replay.
- **Adjacent:** Understand windowing semantics (tumbling, sliding, session), backpressure handling, and checkpoint/savepoint mechanics before committing to either approach.
