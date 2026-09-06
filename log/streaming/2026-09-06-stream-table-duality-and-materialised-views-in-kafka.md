---
date: 2026-09-06
phase: streaming
topic: Stream-table duality and materialised views in Kafka
---

# Stream-table duality and materialised views in Kafka

*Streaming and distributed processing*

## Concept

Stream-table duality is the principle that a stream and a table are two views of the same data: a stream is a changelog (append-only log of events), and a table is the current state materialized from that changelog. In Kafka, this means a topic can be consumed as an event stream (raw events) or as a KTable (compacted state). A materialised view is a persistent, queryable snapshot of a transformation—you compute it once from the stream and keep it updated, rather than recomputing on every query.

This matters because streaming systems must answer two kinds of questions: *what happened?* (event stream) and *what is true now?* (table state). Without materialised views, every query against streaming data either misses late arrivals, re-processes the entire history, or both. With them, you have low-latency point-in-time answers while still capturing the full audit trail in the stream.

It breaks when you treat streams and tables as separate systems. If you log events to Kafka but maintain a separate database for "current state," they diverge under late arrivals, failures, and reprocessing. The duality collapses and you lose either freshness or correctness.

## Practice

**Problem:** Track which job postings are currently open (not yet filled or closed). Maintain a real-time count of open positions per job title and location, updated as postings are added or marked closed. Serve this count to a dashboard with <1 second latency.

```sql
-- Stream: job_events (job_id, event_type: 'posted'|'closed', job_title_short, salary_year_avg, job_work_from_home, job_location, event_timestamp)
-- Solution using Kafka Streams (pseudo-SQL/KSQL):

CREATE TABLE open_jobs AS
  SELECT 
    job_title_short,
    job_location,
    COUNT(*) as open_count,
    LATEST_BY_OFFSET(salary_year_avg) as avg_salary
  FROM job_events
  WHERE event_type = 'posted'
  GROUP BY job_title_short, job_location
  EMIT CHANGES;

-- This materialised view:
-- 1. Reads the job_events stream (changelog)
-- 2. Filters to 'posted' events only
-- 3. Groups by job_title_short and job_location
-- 4. Maintains running count in state store
-- 5. Outputs changes to an internal compacted topic (the table)
-- 6. Queryable via interactive queries or REST in <100ms
```

## Notes

- **Mistake:** assuming a materialised view is "done" after first build. It must be continuously fed new events; a stale view is worse than no view.
- **Mistake:** confusing table compaction (log cleanup policy) with materialised view creation. Compaction is the storage mechanism; a view is the logical structure on top.
- **Adjacent topic:** state stores and exactly-once semantics—a materialised view is only correct if the underlying stream processing guarantees idempotence and handles duplicate events.
- **Revisit:** late-arriving data. A stream that arrives out of order means your materialised view will update retroactively; decide if grace periods or allowed lateness are acceptable.
- **Connected:** CQRS (Command Query Responsibility Segregation)—the stream is the command log, the materialised view is the optimised read model.
