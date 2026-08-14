---
date: 2026-08-14
phase: cloud
topic: Cost monitoring and query governance
---

# Cost monitoring and query governance

*Cloud platforms and storage*

## Concept

Cost monitoring and query governance are mechanisms to track and control spending on cloud data platforms while understanding *why* queries consume resources. Without visibility, a single poorly written query—such as a full table scan on a multi-terabyte dataset or a cartesian join—can incur hundreds of dollars in seconds. Cost monitoring typically involves logging query execution details (rows scanned, data processed, compute time), setting alerts at spend thresholds, and attributing costs to teams or projects. Query governance adds enforcement: query timeout limits, maximum bytes scanned per user, mandatory partition filtering, and approval workflows for expensive operations.

Together, they prevent surprise bills and surface performance problems early. A query that runs in 2 seconds but scans 50 GB is wasteful even if it completes; cost data makes this waste visible. On platforms like BigQuery, Snowflake, and Redshift, ungoverned queries can easily breach budgets, especially during exploratory analysis or when analysts don't understand table statistics. Without governance, teams often discover cost overruns only in retrospective billing reports—too late to prevent the damage.

## Practice

**Problem:** Job posting queries are running slowly and expensively. Analysts frequently query `job_postings_fact` without filtering by `job_posted_date`, causing full table scans. You need to identify expensive queries and enforce partition pruning.

```sql
-- Monitor: Find queries scanning too much data
SELECT
  user_name,
  query_text,
  bytes_scanned,
  bytes_scanned / 1024 / 1024 / 1024 AS gb_scanned,
  total_slot_ms,
  creation_time
FROM `project.region.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE creation_time >= CURRENT_TIMESTAMP() - INTERVAL 24 HOUR
  AND bytes_scanned > 10 * 1024 * 1024 * 1024  -- flag queries scanning >10GB
ORDER BY bytes_scanned DESC;

-- Governance: Enforce partition pruning with a materialized view
-- that raises an error if job_posted_date is not filtered
CREATE OR REPLACE VIEW job_postings_safe AS
SELECT * FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE() - INTERVAL 90 DAY;

-- Better: Optimal query with partition filter
SELECT
  job_title_short,
  AVG(salary_year_avg) AS avg_salary,
  SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) AS remote_count
FROM job_postings_fact
WHERE job_posted_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY job_title_short
ORDER BY avg_salary DESC;
```

## Notes

- **Partition and cluster awareness**: Always filter on partition columns (e.g., `job_posted_date`) first; this is where governance rules should start. Clustered columns (e.g., `job_location`) are secondary optimizations.
- **Attribution and chargeback**: Assign query costs to users or teams via labels/tags in your execution logs so accountability drives behavior change. Without knowing "who paid," governance lacks teeth.
- **Adjacent topics**: Query performance optimization (EXPLAIN plans, index strategies) and data catalog governance (knowing which tables exist and their size) are prerequisites; cost governance is the enforcement layer.
- **Common pitfall**: Focusing only on query count, not query cost. A small number of expensive queries can dwarf thousands of cheap ones; prioritize high-cost outliers.
- **Revisit regularly**: Query patterns and data volumes change; re-calibrate cost thresholds and partition strategies quarterly to stay aligned with growth.
