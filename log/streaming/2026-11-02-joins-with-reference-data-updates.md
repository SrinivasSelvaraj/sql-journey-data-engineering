---
date: 2026-11-02
phase: streaming
topic: Joins with reference data updates
---

# Joins with reference data updates

*Streaming and distributed processing*

## Concept

Joining streams with reference data that updates over time creates a temporal mismatch problem: the reference data you join with depends on *when* the join happens, not when the data was originally created. In streaming pipelines, a job posting arriving at 2pm might join against a salary lookup table that was updated at 3pm, giving it information it shouldn't have. This violates causality and produces incorrect historical analytics.

The core challenge is that reference tables (location codes, skill taxonomies, salary bands) evolve continuously. Without explicit versioning or watermarking, you lose traceability of which version of reference data applied to which event. In distributed systems, this gets worse: different workers might see different versions of the reference table mid-pipeline, causing non-deterministic joins.

Solutions involve capturing the reference table's state at the time the event arrived—either through slowly-changing dimension (SCD) patterns with effective dates, or by embedding the join result as enriched fields at ingestion time rather than performing joins downstream.

## Practice

**Problem:** You're building a real-time dashboard of job postings. Job postings stream in with a `job_location` field (e.g., "San Francisco"), but your location reference table gets updated whenever a city's salary market changes. You need to join each posting to the *correct* salary band that was active on the posting date, not today's salary band.

```sql
-- Assume a location_salary_bands SCD Type 2 table:
-- (location, salary_band, effective_date, end_date)

SELECT 
  jp.job_id,
  jp.job_title_short,
  jp.job_posted_date,
  jp.job_location,
  lsb.salary_band,
  lsb.effective_date
FROM job_postings_fact jp
LEFT JOIN location_salary_bands lsb
  ON jp.job_location = lsb.location
  AND jp.job_posted_date >= lsb.effective_date
  AND (jp.job_posted_date < lsb.end_date OR lsb.end_date IS NULL)
ORDER BY jp.job_posted_date, jp.job_id;
```

The key: the join condition includes a date range check. The posting only matches the salary band version that was *active* on its posted date, not whichever version exists in the reference table today.

## Notes

- **Temporal join mistakes:** Forgetting to add effective/end date bounds means you're doing a non-deterministic join; test with historical data to catch this.
- **SCD Type 2 is your friend:** Slowly-changing dimensions with effective dates are the standard pattern for versioned reference data in data warehouses; learn Type 1 vs. Type 2 vs. Type 3 trade-offs.
- **Late-arriving reference updates:** If a reference table update arrives *after* events that should use it, you may need to backfill or replay events—design your retention windows accordingly.
- **Broadcast joins in Spark:** In distributed systems, reference tables are often broadcast to all workers; ensure your broadcast is fresh and consider caching versioned snapshots rather than live tables.
- **Related: Watermarks & allowed lateness:** Streaming frameworks use watermarks to define "event time completeness"; reference joins should respect these bounds to avoid joining against future versions.
