---
date: 2026-11-07
phase: sql
topic: Explain analyze: actual vs estimated rows and runtime
---

# Explain analyze: actual vs estimated rows and runtime

*SQL for analytics and engineering*

## Concept

When SQL engines execute queries, the optimizer estimates how many rows will flow through each operation (estimated rows) based on statistics, but the actual execution may process a different number (actual rows). A large gap between estimated and actual reveals optimizer blindness: the plan was chosen based on wrong assumptions. This matters because a suboptimal plan chosen for 100 rows might catastrophically fail on 100,000 rows—or vice versa, wasting resources on an over-provisioned approach.

Runtime also shifts based on actual vs. estimated: an operation chosen because it was estimated to be cheap (e.g., nested loop join) can become the bottleneck if actual cardinality is 10× higher. Conversely, the optimizer might choose an expensive operation (e.g., hash aggregate) when actual rows are tiny. Without analyzing this gap, you'll ship queries that mysteriously slow down after a data refresh or fail under real load during an interview.

The fix: inspect execution plans (EXPLAIN ANALYZE in PostgreSQL, actual execution stats in SQL Server, etc.), identify where estimates diverge sharply from reality, and either rewrite the query to help the optimizer (better joins, explicit predicates) or update statistics if they're stale.

## Practice

**Problem:** You've written a query joining `job_postings_fact` to itself to find duplicate postings (same title, location, salary posted within 30 days). The plan shows an estimated 500 rows but actual is 45,000. The query runs in 3 seconds in dev, but times out in production. Why?

```sql
EXPLAIN ANALYZE
SELECT 
  a.job_id,
  b.job_id AS duplicate_job_id,
  a.job_title_short,
  a.job_location
FROM job_postings_fact a
INNER JOIN job_postings_fact b
  ON a.job_title_short = b.job_title_short
  AND a.job_location = b.job_location
  AND ABS(EXTRACT(DAY FROM a.job_posted_date - b.job_posted_date)) <= 30
  AND a.job_id < b.job_id
WHERE a.salary_year_avg > 50000
GROUP BY a.job_id, b.job_id, a.job_title_short, a.job_location;
```

**Root cause:** The optimizer doesn't understand that `ABS(EXTRACT(DAY FROM ...)) <= 30` is highly selective; it estimates far fewer matches than actually exist. The filter isn't pushed into the join early enough.

**Solution:** Filter `job_posted_date` range *before* the join and add a computed column index:

```sql
EXPLAIN ANALYZE
SELECT 
  a.job_id,
  b.job_id AS duplicate_job_id,
  a.job_title_short,
  a.job_location
FROM (
  SELECT * FROM job_postings_fact 
  WHERE salary_year_avg > 50000
    AND job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
) a
INNER JOIN (
  SELECT * FROM job_postings_fact 
  WHERE salary_year_avg > 50000
    AND job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
) b
  ON a.job_title_short = b.job_title_short
  AND a.job_location = b.job_location
  AND a.job_posted_date BETWEEN b.job_posted_date - INTERVAL '30 days' 
    AND b.job_posted_date + INTERVAL '30 days'
  AND a.job_id < b.job_id
GROUP BY a.job_id, b.job_id, a.job_title_short, a.job_location;
```

The date predicate is now explicit and pushable; actual rows should align with estimated, and the join becomes index-friendly.

## Notes

- **Estimate blindness with functions:** The optimizer can't estimate cardinality through `ABS()`, `SUBSTRING()`, or custom functions—push logic into explicit WHERE clauses instead.
- **Stale statistics:** If actual >> estimated consistently, run `ANALYZE` (PostgreSQL) or `UPDATE STATISTICS` (SQL Server) to refresh the optimizer's baseline.
- **Self-joins and non-equijoins:** Cartesian products disguised as joins are a common source of massive estimation errors; add early, tight filters.
- **Spill to disk:** When actual rows exceed memory allocated for a sort or hash aggregate, the query spills to disk and runtime explodes—this is often the first signal something is wrong.
- **Interview red flag:** If you can't read EXPLAIN output or don't know where to check actual vs. estimated, ask the interviewer how to access the plan and walk through it aloud; this shows you debug systematically, not by guessing.
