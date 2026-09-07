---
date: 2026-09-07
phase: streaming
topic: Watermark propagation across operators
---

# Watermark propagation across operators

*Streaming and distributed processing*

## Concept

Watermark propagation is the mechanism that carries a timestamp through a streaming pipeline, signaling to each operator "all events before this time have arrived." A watermark at time T means no earlier events will appear downstream. Without watermark propagation, operators cannot safely trigger aggregations or close windows—they risk either emitting incomplete results or waiting indefinitely.

The watermark originates at the source (often as max event time seen so far, minus allowed lateness), then flows through each operator. Each operator must either pass the watermark forward unchanged or update it based on its own logic. When watermarks stall or break between operators, late-arriving data silently drops, stateful computations hang, and joins produce incomplete results. This matters most for windowed aggregations, session windows, and time-sensitive joins where correctness depends on knowing when a time period is truly closed.

Without explicit watermark propagation, a streaming system defaults to wall-clock time (processing time), which is order-independent but meaningless for business logic—a job posting delay in your data pipeline shouldn't change historical salary analytics. Watermarks tie correctness to event time, the only time domain that reflects what actually happened.

## Practice

**Problem:** You need to compute hourly average salary by job location for postings that arrived within one day of posting. Late arrivals after 24 hours should be dropped, but you must not emit partial results before the hour closes.

```sql
SELECT
  TUMBLE_START(job_posted_date, INTERVAL '1' HOUR) AS hour_start,
  job_location,
  AVG(salary_year_avg) AS avg_salary,
  COUNT(*) AS posting_count
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY
  TUMBLE(job_posted_date, INTERVAL '1' HOUR),
  job_location;
```

Configuration (in Flink/Kafka Streams):
- Source watermark strategy: `forMonotonousTimestamps()` on `job_posted_date`, with `withIdleness(Duration.ofMinutes(5))` to advance watermarks when no events arrive.
- Allowed lateness: `allowedLateness(Duration.ofDays(1))`.
- Window closure: tumbling window automatically closes and fires when watermark passes window end + lateness threshold. Watermarks flow through the GROUP BY and into any downstream operator unchanged.

## Notes

- **Watermark stalls are silent killers:** If a slow partition or idle source never updates its watermark, downstream windows never close. Use idleness detection and source coalescence to prevent this.
- **Watermarks vs. triggers:** Watermarks determine *when* a window is ready; triggers determine *what* to emit. Combining event-time watermarks with early and late triggers gives you flexibility (emit speculative results, then refinements).
- **Multi-input operators need special care:** Joins and coGroups receive watermarks from *all* input streams; the operator advances only to the minimum watermark across inputs. A slow join side blocks the fast side.
- **Watermarks are not monotonic by default:** Operators must enforce monotonicity or emit `MAX(watermark, previous_watermark)` to avoid out-of-order watermark messages, which violate the contract.
- **Adjacent topic—backpressure & buffering:** Watermark propagation speed interacts with buffering policy. If an operator buffers aggressively, watermarks pile up inside; if it applies aggressive backpressure, the source slows and watermarks lag real time.
