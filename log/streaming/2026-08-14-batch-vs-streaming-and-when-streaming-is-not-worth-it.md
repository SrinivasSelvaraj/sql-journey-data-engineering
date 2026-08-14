---
date: 2026-08-14
phase: streaming
topic: Batch vs streaming and when streaming is not worth it
---

# Batch vs streaming and when streaming is not worth it

*Streaming and distributed processing*

## Concept

Batch processing collects data over a time window (hourly, daily) and processes it all at once, while streaming processes data continuously as it arrives. Streaming excels when you need sub-second decisions—fraud detection, real-time alerting, or live dashboards. However, streaming introduces complexity: you must handle out-of-order arrivals, manage state across distributed nodes, and tune for latency vs. cost tradeoffs. Batch is worth using when the business requirement allows for delay—daily reporting, weekly analytics, monthly billing—because it's simpler to build, easier to debug, and cheaper to operate at scale.

The critical question isn't "should we stream?" but "what's the cost of staleness?" If a job posting dashboard can refresh hourly, batch wins. If fraud must be caught within milliseconds, streaming is mandatory. Many teams fall into the trap of streaming everything "just in case," paying 3–5x infrastructure costs for data that doesn't need real-time processing. Streaming is also harder to test, monitor, and recover from failures; a batch job that fails at 2 AM can be re-run; a streaming job that crashes loses in-flight state and requires careful recovery logic.

## Practice

**Problem:** Your analytics team wants to track job posting volume by location every 5 minutes to detect market shifts. The business can tolerate a 5-minute delay, but batch jobs run hourly. Which approach should you use?

**Answer:** Use a streaming solution here because the 5-minute window is tighter than your batch schedule. But if the requirement were "by end of day," batch is simpler:

```sql
-- Batch approach (hourly or daily): simpler, cheaper
INSERT INTO job_postings_summary (location, posting_count, summary_hour)
SELECT 
  job_location,
  COUNT(*) as posting_count,
  DATE_TRUNC('hour', job_posted_date) as summary_hour
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 hour'
GROUP BY job_location, DATE_TRUNC('hour', job_posted_date);

-- Streaming approach (5-min windows): handle late arrivals
-- In Kafka + Flink/Spark Streaming:
-- - Tumbling window of 5 minutes
-- - Allowed lateness: 2 minutes (catch delayed arrivals)
-- - Trigger on: every new message or time interval
```

## Notes

- **Streaming false positive:** Not every "always-on" requirement needs streaming. A job alert system can still use batch processing every 15 minutes if the alert delay is acceptable to users.

- **State management trap:** Streaming requires you to maintain mutable state (running counts, user sessions). Batch avoids this entirely; your data is immutable snapshots. Stateful streaming is where bugs hide.

- **Out-of-order data:** In streaming, a job posted 5 minutes ago might arrive now due to network delays. Batch sidesteps this by waiting for a full collection window before processing.

- **Adjacent topic—lambda architecture:** Some teams run both batch and stream in parallel, using stream for speed and batch for correctness. This adds operational burden; only do it if one pipeline truly cannot meet your SLA.

- **Worth revisiting:** Event time vs. processing time, watermarks for late data, and cost modeling (GB processed per insight gained). Revisit this decision when requirements change.
