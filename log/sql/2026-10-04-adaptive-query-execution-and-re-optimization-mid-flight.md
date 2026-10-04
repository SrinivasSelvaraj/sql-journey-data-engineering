---
date: 2026-10-04
phase: sql
topic: Adaptive query execution and re-optimization mid-flight
---

# Adaptive query execution and re-optimization mid-flight

*SQL for analytics and engineering*

## Concept

Adaptive query execution (AQE) is a runtime optimization technique where the query engine re-plans parts of a query *during* execution, based on actual statistics gathered from intermediate results. Rather than committing to a single plan at compile time, the engine observes cardinality, data skew, and join selectivity as data flows through operators, then pivots the strategy if assumptions were wrong.

This matters acutely when:
- **Cardinality estimates are stale or wrong** (e.g., a `WHERE job_work_from_home = true` filter was predicted to cut 50% of rows but actually removes 99%, or vice versa)
- **Join order is sensitive to skew** (a broadcast join fails because one side is larger than memory; a sort-merge join becomes cheaper mid-flight)
- **Multi-stage aggregations have unpredictable group counts** (GROUP BY job_title_short could produce 100 or 1M groups; downstream operators need to adapt)

Without AQE, a query planner commits to bad decisions early: choosing hash join when sort-merge is faster, broadcasting a 10GB table, or allocating memory for 1M groups when 100 exist. The query runs to completion but slowly. AQE detects these failures and re-optimizes on the fly.

## Practice

**Problem:**  
You have a reporting query that joins `job_postings_fact` (2M rows) to a high-cardinality `company_dim` table (50K companies). A naive planner might broadcast `company_dim` assuming it's small, but in reality 30K companies have posted jobs, and metadata bloats the table to 4GB—exceeding broadcast memory. Write a query and explain how AQE would help; then show how to hint the optimizer.

```sql
-- Vulnerable query (planner assumes company_dim is small)
SELECT 
  c.company_name,
  COUNT(*) as job_count,
  AVG(j.salary_year_avg) as avg_salary
FROM job_postings_fact j
INNER JOIN company_dim c ON j.company_id = c.company_id
WHERE j.job_posted_date >= '2024-01-01'
GROUP BY c.company_name
ORDER BY job_count DESC;

-- With AQE (Spark, Databricks):
-- Engine scans company_dim, realizes size > broadcast threshold,
-- converts to sort-merge join mid-execution.

-- Explicit hint to force sort-merge (Spark SQL):
SELECT 
  /*+ USE_SORT_MERGE(j, c) */
  c.company_name,
  COUNT(*) as job_count,
  AVG(j.salary_year_avg) as avg_salary
FROM job_postings_fact j
INNER JOIN company_dim c ON j.company_id = c.company_id
WHERE j.job_posted_date >= '2024-01-01'
GROUP BY c.company_name
ORDER BY job_count DESC;

-- Or shuffle and sort both sides explicitly:
SELECT 
  c.company_name,
  COUNT(*) as job_count,
  AVG(j.salary_year_avg) as avg_salary
FROM (SELECT * FROM job_postings_fact WHERE job_posted_date >= '2024-01-01') j
INNER JOIN company_dim c ON j.company_id = c.company_id
GROUP BY c.company_name
ORDER BY job_count DESC;
```

## Notes

- **Cardinality estimation is the root cause:** AQE is a band-aid for bad estimates. Collect accurate stats (`ANALYZE TABLE`) and keep histograms fresh. Stale stats defeat AQE.
- **Join size miscalculation is the #1 culprit:** A 5GB table misreported as 500MB gets broadcast, spills to disk, and tanks performance. Monitor actual vs. estimated partition sizes in execution plans.
- **AQE has latency overhead:** Re-optimization adds CPU and can delay execution. Disable for simple, predictable queries; enable for complex multi-join OLAP workloads.
- **Connects to: query plan caching, partition pruning, dynamic partition elimination.** AQE complements these; together they form robust adaptive execution.
- **Tool-specific:** Spark 3.0+ has AQE enabled by default (`spark.sql.adaptive.enabled=true`). Postgres and MySQL lack native AQE; BigQuery and Redshift have limited forms. Know your engine's capabilities during interviews.
