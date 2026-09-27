---
date: 2026-09-27
phase: streaming
topic: Out-of-order event handling and allowed lateness
---

# Out-of-order event handling and allowed lateness

*Streaming and distributed processing*

## Concept

Out-of-order event handling addresses the reality that data arriving in a streaming system often violates timestamp order. A user's click event might arrive 30 seconds late due to network delay; a mobile app's offline buffer might deliver events hours after they occurred. Without accounting for this, windowed aggregations close prematurely and exclude valid late data, producing incorrect counts and metrics.

Allowed lateness is a configuration that keeps a window open past its trigger time to accept straggling events. Instead of discarding an event with timestamp T that arrives after the window [T-1h, T] has already fired, you specify a grace period—say, 5 minutes—allowing the window to update. This is essential for accuracy in real-world systems where SLAs rarely guarantee in-order delivery.

The cost is state retention: keeping windows open longer consumes memory and increases operator complexity. You must balance accuracy against resource constraints. Systems like Flink, Kafka Streams, and BigQuery all expose allowed lateness as a tunable parameter; choosing it requires understanding your data's actual lateness distribution and your acceptable margin of error.

## Practice

**Problem:** You ingest job postings with a `job_posted_date` timestamp. Some postings arrive 2–3 days late (delayed ETL pipelines, data corrections). You want to count new jobs posted each day, but late arrivals should still be attributed to their correct posted date and update yesterday's count if it arrives today.

```sql
-- Flink SQL example: windowed count with allowed lateness
SELECT
  TUMBLE_START(job_posted_date, INTERVAL '1' DAY) as posting_day,
  COUNT(DISTINCT job_id) as job_count,
  MAX(job_posted_date) as latest_event_time
FROM job_postings_fact
GROUP BY TUMBLE(job_posted_date, INTERVAL '1' DAY)
HAVING MAX(job_posted_date) > CURRENT_TIMESTAMP - INTERVAL '3' DAY;

-- In stream processing code (pseudocode):
stream
  .keyBy(job => job.posting_date)
  .window(TumblingEventTimeWindow.of(Duration.ofDays(1)))
  .allowedLateness(Duration.ofDays(3))  -- Keep window open 3 days past close
  .aggregate(new CountAggregator())
  .addSink(output);
```

The `allowedLateness(Duration.ofDays(3))` directive keeps each day's window open for three additional days, accepting corrections and late arrivals while still attributing them to their original `job_posted_date`.

## Notes

- **Common mistake:** Confusing event time (when the event truly occurred) with processing time (when it arrives). Always use event time for windowing; processing time windows are vulnerable to late data and system delays.
- **State explosion:** Allowed lateness increases memory usage proportionally. Monitor state size in production; if it grows unbounded, lower the grace period or implement state cleanup policies.
- **Watermarks:** Related concept—a watermark signals how far behind event time processing currently is. It drives window closure; windows close when the watermark passes their end time + allowed lateness.
- **Backfill vs. reprocessing:** Late data that arrives weeks later may require full recomputation. Decide upfront: are you updating results incrementally (allowed lateness) or recomputing historical windows (batch replay)?
- **Dead-letter queues:** Data exceeding allowed lateness should be routed to a separate topic/sink for investigation, not silently dropped.
