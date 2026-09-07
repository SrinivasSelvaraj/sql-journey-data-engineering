---
date: 2026-09-07
phase: streaming
topic: CoGroup and multi-stream processing patterns
---

# CoGroup and multi-stream processing patterns

*Streaming and distributed processing*

## Concept

CoGroup (co-partitioned group) is an operation that joins two or more streams or datasets by their key, producing grouped tuples where elements with matching keys are bundled together. Unlike a traditional join that emits a single row per match, cogroup preserves the collection structure—you get back grouped iterables keyed by the join attribute. This matters in streaming because data arrives out of order and in micro-batches; cogroup lets you collect all events for a key before deciding how to process them, avoiding premature aggregation.

Without cogroup, you face three hard problems: (1) joining streams at different arrival rates without losing data, (2) handling late-arriving facts that should retroactively affect earlier results, and (3) correlating multiple event types (e.g., clicks and purchases) by user without materializing an expensive full outer join. CoGroup defers the decision of what to do with grouped data, keeping your logic composable and your state management explicit.

In distributed streaming frameworks (Spark Structured Streaming, Kafka Streams, Flink), cogroup is the primitive that enables sessionization, multi-stream enrichment, and complex event detection—anywhere you need to say "for each key, give me *all* the records from stream A *and* all the records from stream B, then I'll decide how to combine them."

## Practice

**Problem:** You have two event streams: one for job postings and one for job application events. You need to correlate them by job_id to enrich postings with application counts and compute the average salary *only for jobs that received applications*. A cogroup lets you group postings and applications by job_id, then emit a single enriched record per job.

```sql
-- Simulating cogroup logic in SQL using window functions + outer joins
WITH job_postings_grouped AS (
  SELECT
    job_id,
    COLLECT_LIST(STRUCT(job_title_short, salary_year_avg, job_posted_date)) AS postings
  FROM job_postings_fact
  WHERE job_posted_date >= DATE_SUB(CURRENT_DATE, INTERVAL 30 DAY)
  GROUP BY job_id
),
applications_grouped AS (
  SELECT
    job_id,
    COUNT(*) AS app_count,
    COLLECT_LIST(applicant_id) AS applicants
  FROM job_applications_fact
  GROUP BY job_id
)
SELECT
  p.job_id,
  p.postings[0].job_title_short,
  p.postings[0].salary_year_avg,
  COALESCE(a.app_count, 0) AS application_count,
  COALESCE(a.applicants, ARRAY()) AS applicant_list
FROM job_postings_grouped p
LEFT JOIN applications_grouped a ON p.job_id = a.job_id
WHERE a.app_count > 0 OR a.app_count IS NULL;
```

## Notes

- **Keying must be consistent:** both streams must be partitioned by the same key (job_id here). Mismatched partitioning silently produces incomplete results—validate upstream.
- **State explosion:** cogroup accumulates all records for each key in memory. Without TTL or watermark cleanup, long-tail keys (jobs with very old postings) bloat state indefinitely.
- **Ordering illusion:** cogroup doesn't guarantee order *within* each group. If you need temporal sequence (e.g., "posting then application"), add timestamps and sort inside the grouped collection.
- **Late-arriving data:** set appropriate watermark delays (e.g., `withWatermark("job_posted_date", "7 days")`) so that late applications still match their postings. No watermark = unbounded state or data loss.
- **Adjacent patterns:** stream-stream join, sessionWindow, `statefulMapGroupsWithState()` in Spark—cogroup is the foundation, but choosing between eager join vs. deferred cogroup depends on whether you want results immediately or can wait to batch-process entire key groups.
