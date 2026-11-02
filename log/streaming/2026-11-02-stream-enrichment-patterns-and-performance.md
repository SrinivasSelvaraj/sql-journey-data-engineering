---
date: 2026-11-02
phase: streaming
topic: Stream enrichment patterns and performance
---

# Stream enrichment patterns and performance

*Streaming and distributed processing*

## Concept

Stream enrichment adds context to events by joining them with slowly-changing reference data (dimensions, lookup tables, or other streams) as they flow through the pipeline. Without enrichment, your events remain sparse—a job application event has only an applicant ID, but no job title, salary band, or location context. The challenge is deciding *when* to look up that context: too early and you miss updates; too late and you create bottlenecks.

Performance breaks when enrichment logic performs blocking I/O (database calls) for every record, or when you join two high-volume streams without windowing strategy. A 10,000 event/sec stream that makes a synchronous database lookup per event becomes a I/O bottleneck within seconds. Conversely, caching stale reference data leads to incorrect enrichment and silent data quality failures that are hard to debug.

The practical pattern is: batch-load reference data into fast-access storage (local cache, broadcast variable, or state store), enrich in-memory, and periodically refresh the cache. For reference data that changes frequently, use versioned snapshots with effective dates or stream the reference data itself to keep enrichment tables synchronized.

## Practice

**Problem:** You receive a stream of job applications with only `job_id` and `applicant_id`. Enrich each application with job title, salary, and work-from-home status from `job_postings_fact`. The table is updated daily but doesn't change mid-day; however, you need the salary band *at the time the application was received*, not today's salary.

```sql
-- Solution: Use a temporal join with versioned reference data
-- Assume job_postings_fact has job_posted_date as the version key

WITH applications_stream AS (
  SELECT 
    applicant_id,
    job_id,
    application_timestamp,
    ROW_NUMBER() OVER (PARTITION BY applicant_id ORDER BY application_timestamp) as seq
  FROM incoming_applications
),
enriched AS (
  SELECT 
    a.applicant_id,
    a.job_id,
    a.application_timestamp,
    j.job_title_short,
    j.salary_year_avg,
    j.job_work_from_home,
    j.job_posted_date
  FROM applications_stream a
  LEFT JOIN job_postings_fact j
    ON a.job_id = j.job_id
    AND j.job_posted_date <= DATE(a.application_timestamp)
    AND (j.job_posted_date = (
      SELECT MAX(job_posted_date) 
      FROM job_postings_fact j2 
      WHERE j2.job_id = a.job_id 
        AND j2.job_posted_date <= DATE(a.application_timestamp)
    ))
)
SELECT * FROM enriched;
```

## Notes

- **Synchronous lookups kill throughput**: Always batch-load reference data or use a state store rather than querying an external database per record. Even 5ms latency per event becomes 50 seconds of delay at 10k events/sec.

- **Version your reference data**: Use effective dates or sequence numbers on reference tables so you can join on "the state of this dimension *when this event occurred*," not "the current state."

- **Broadcast vs. state store trade-off**: Small reference tables (<100MB) fit in broadcast variables (in-memory on all workers); larger ones need a queryable state store (RocksDB in Flink, materialized views in Kafka Streams).

- **Watch for join explosion**: Enriching a stream against another stream (not a static table) requires windowing and deduplication, or you'll produce Cartesian products. Always window-join two streams, never inner-join without bounds.

- **Monitor staleness and gaps**: Log when enrichment fails (reference data missing) versus when it succeeds. Stale enrichment data silently corrupts downstream analytics—set up alerts on cache age and join match rates.
