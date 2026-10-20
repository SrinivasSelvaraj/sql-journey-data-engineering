---
date: 2026-10-20
phase: reliability
topic: Load testing and stress testing for pipelines
---

# Load testing and stress testing for pipelines

*Quality, reliability and the professional layer*

## Concept

Load and stress testing reveal how your pipeline behaves at scale—not just whether it works. Load testing pushes realistic volume through your system to measure latency, throughput, and resource consumption. Stress testing exceeds normal capacity to find breaking points: where does it fail? At 10M rows or 100M? When memory spikes? These tests catch problems that unit tests and small-dataset validation miss entirely.

Without load testing, you deploy pipelines that work fine on dev data but collapse in production. A transformation that takes 2 seconds on 1,000 records might time out on 50M. A join that seemed efficient locks tables unexpectedly under concurrent load. You don't learn about these until a business process stalls and you're debugging under pressure.

This is what separates builders from owners: builders ship; owners know the failure modes and have tested them.

## Practice

**Problem:** Your `job_postings_fact` table receives daily incremental loads of 50K–200K rows. You need to validate that your aggregation pipeline (counting jobs by title and location, calculating median salary) remains performant as the table grows to 10M+ historical rows.

```sql
-- Load test: simulate 10M row table and measure aggregation performance
WITH large_dataset AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location
  FROM job_postings_fact
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '730 days'
)
SELECT
  job_title_short,
  job_location,
  COUNT(*) as job_count,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as median_salary,
  COUNT(CASE WHEN job_work_from_home THEN 1 END) as remote_count
FROM large_dataset
GROUP BY job_title_short, job_location
HAVING COUNT(*) > 100;
```

Run this with `EXPLAIN ANALYZE` to check execution time, index usage, and memory. Then progressively increase the date range and measure degradation. If it exceeds your SLA (e.g., must complete in < 5 minutes), identify bottlenecks: missing indexes, full table scans, or need for materialized views.

## Notes

- **Index your predicates first.** Load testing exposes missing indexes on filter and join columns; add them *before* stress testing to get meaningful results about your actual logic, not bad indexing.
- **Test with production-like schemas.** Using a tiny dev copy masks real problems: row width, data skew, concurrent writes, and lock contention only show up at scale.
- **Stress testing != chaos engineering.** You're finding limits, not breaking things randomly. Test specific failure modes: max concurrent connections, full disk, network latency—then document the failure mode and mitigation.
- **Adjacent: monitoring and alerting.** Load tests define your baselines (normal CPU, execution time, memory). Set alerts *just below* those baselines so you catch degradation before users do.
- **Revisit after schema changes.** New columns, partitioning, or join logic can break assumptions from old load tests. Re-baseline quarterly or after major DDL changes.
