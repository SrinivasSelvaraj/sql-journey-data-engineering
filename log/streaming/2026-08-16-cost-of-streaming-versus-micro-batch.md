---
date: 2026-08-16
phase: streaming
topic: Cost of streaming versus micro-batch
---

# Cost of streaming versus micro-batch

*Streaming and distributed processing*

## Concept

Streaming and micro-batch represent fundamentally different trade-offs in latency, throughput, and operational cost. Streaming processes events as they arrive (millisecond-scale latency), keeping state hot in memory and triggering computation immediately; micro-batch collects events into small windows (seconds to minutes) and processes them as discrete batches, reducing context switching and leveraging economies of scale. The cost difference emerges from infrastructure: streaming requires always-on clusters with continuous memory overhead and frequent state checkpoints, while micro-batch can scale compute up and down between windows and compress multiple events into fewer, more efficient operations.

Streaming matters when you need sub-second decisions (fraud detection, real-time alerts) or when SLA requires fresh state. It breaks when your cluster cannot sustain the per-event processing cost—a single spike in event volume can exhaust memory or cause cascading backpressure. Micro-batch works well for dashboards, aggregations, and workflows where 30–60 second staleness is acceptable, but fails when you cannot absorb the window delay or when late-arriving events violate your consistency model.

In practice, the choice is rarely pure: most systems hybrid, using micro-batch for cost-efficient bulk aggregations (hourly job-posting volume tallies) and streaming for low-latency enrichment (tagging new postings with region-of-interest in milliseconds). Understanding your event rate, tolerance for lateness, and state size is essential—a job-posting stream at 100 events/sec with lightweight state favors streaming; the same stream at 100k/sec with complex joins may force micro-batch or require distributed streaming infrastructure like Kafka + Flink.

## Practice

**Problem:** You need to track the average salary and posting frequency for each job title *in real time*, updating a dashboard every 5 seconds. Event arrival is bursty (job boards post in waves), and you must handle late arrivals (postings timestamped yesterday arrive today). Compare the operational cost of streaming versus 5-second micro-batches.

**Streaming solution** (Kafka + Flink or Spark Structured Streaming):
```sql
SELECT 
  job_title_short,
  COUNT(*) AS postings_count,
  AVG(salary_year_avg) AS avg_salary,
  CURRENT_TIMESTAMP AS window_end
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day'
GROUP BY job_title_short
EMIT CHANGES;  -- or continuous mode in Spark
```
Cost: cluster always running, state (per title aggregates) held in memory, frequent checkpoints to prevent data loss on failure.

**Micro-batch solution** (Spark Structured Streaming or Flink mini-batch):
```sql
SELECT 
  job_title_short,
  COUNT(*) AS postings_count,
  AVG(salary_year_avg) AS avg_salary,
  WINDOW(job_posted_date, '5 seconds') AS batch_window
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day'
GROUP BY job_title_short, WINDOW(job_posted_date, '5 seconds')
ORDER BY batch_window DESC;
```
Cost: cluster spins down between batches, 5-second latency acceptable for dashboard, late arrivals handled in next batch.

For this use case, **micro-batch saves 40–60% on compute cost** if your BI tool can tolerate 5–10 second refresh, and eliminates the memory pressure of holding unbounded state.

## Notes

- **Common mistake:** confusing event time (when posted_date occurs) with processing time (when it arrives). Micro-batch windowing on processing time loses semantics; use event-time windows with watermarks to handle late arrivals correctly.
- **Late-arrival handling:** streaming excels at out-of-order tolerance via watermarks and allowed lateness; micro-batch requires explicit reprocessing or a "catch-up" batch for stragglers.
- **Adjacent topics:** distributed joins (expensive in both modes, but streaming state grows unbounded), exactly-once semantics (more complex in streaming; micro-batch often gets it free), and backpressure (streaming must slow source on overload; micro-batch queues then rescales).
- **Revisit:** the hybrid pattern—use micro-batch for hourly aggregations (cost-effective), stream for alerting on individual postings (low latency). Also benchmark your platform's overhead; Spark Structured Streaming adds 1–2s per micro-batch, changing the calculus.
- **State size matters:** if you track salary histograms or top-K jobs per region, streaming state explodes quickly. Micro-batch sidesteps this by discarding state after each window.
