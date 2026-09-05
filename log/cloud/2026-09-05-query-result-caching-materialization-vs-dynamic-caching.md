---
date: 2026-09-05
phase: cloud
topic: Query result caching: materialization vs dynamic caching
---

# Query result caching: materialization vs dynamic caching

*Cloud platforms and storage*

## Concept

Query result caching stores the output of expensive computations so repeated identical queries return instantly instead of rescanning data. **Materialization** pre-computes and persists results (e.g., as a table or view refresh on a schedule), trading storage cost for guaranteed fast reads. **Dynamic caching** (used by Snowflake, BigQuery, Redshift) automatically detects identical query patterns and reuses results within a short TTL (typically 24 hours), requiring zero maintenance but only helping if the exact query repeats.

Materialization matters when the same aggregation runs repeatedly but the underlying table changes slowly—e.g., daily revenue dashboards querying millions of rows. Dynamic caching saves money on identical ad-hoc queries (common in dashboards hitting the same filters). Without either, a 30-second scan of 1 billion rows runs 30 seconds every time, multiplying your compute bill and user wait time.

The key tradeoff: materialization requires you to manage staleness and storage; dynamic caching is "free" but only works for exact query matches and won't help if each query is slightly different (different date range, different user ID).

## Practice

**Problem:** Your analytics dashboard runs 50 queries daily filtering job postings by `job_work_from_home = true` and aggregating salary by `job_title_short`. Each query scans 5 million rows and takes 8 seconds. You pay per byte scanned. How do you reduce cost and latency?

**Materialized table solution:**

```sql
-- Create materialized summary (refresh nightly)
CREATE TABLE job_postings_remote_summary AS
SELECT 
  job_title_short,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary,
  MAX(job_posted_date) as most_recent_date
FROM job_postings_fact
WHERE job_work_from_home = true
GROUP BY job_title_short;

-- Dashboard queries hit this instead
SELECT job_title_short, avg_salary, posting_count
FROM job_postings_remote_summary
ORDER BY avg_salary DESC;
```

This replaces 8 seconds + 5M row scan with <100ms on a small table. Cost drops ~99% if the dashboard runs 50 times daily. Tradeoff: salary figures are up to 24 hours stale, and you own the refresh logic.

## Notes

- **Exact match requirement for dynamic caching**: Adding `LIMIT 100` to an otherwise identical query breaks the cache hit. Only use dynamic caching for truly identical repeated queries; for slight variations, materialize instead.
- **Storage cost creep**: Materializing summaries looks free until you have 200 summary tables. Track materialized view sizes and archive old ones.
- **Staleness SLA**: Agree on acceptable lag before choosing refresh frequency. Remote-work postings change hourly; materialized refreshing nightly may be too stale for operational dashboards.
- **Adjacent topic**: Query compilation vs execution time—caching bypasses both, but understanding which bottleneck dominates (compile or scan) tells you if caching even helps.
- **Revisit when**: A dashboard runs 50× per day but queries differ by date range each time → neither caching strategy works alone; you need aggregation tables + predicate pushdown, or accept the cost.
