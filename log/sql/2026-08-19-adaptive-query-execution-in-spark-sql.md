---
date: 2026-08-19
phase: sql
topic: Adaptive query execution in Spark SQL
---

# Adaptive query execution in Spark SQL

*SQL for analytics and engineering*

## Concept

Adaptive query execution (AQE) is Spark SQL's runtime optimization that replaces suboptimal execution plans *mid-query* using statistics collected from completed stages. Instead of committing to a single plan at compile time, AQE monitors shuffle output sizes, skewed partitions, and join cardinalities, then dynamically adjusts decisions like join strategy (broadcast vs. sort-merge) or partition coalescing.

This matters because initial cardinality estimates are often wildly wrong—especially after filters, aggregations, or complex joins where statistics are stale or unavailable. Without AQE, a query planner might choose a sort-merge join expecting 100M rows, only to find after the first shuffle that one side has 50K rows (ideal for broadcast). AQE catches this and replans; without it, you waste I/O and network bandwidth.

AQE breaks down when: (1) you disable it (still the default in some older configs), (2) shuffle statistics are missing due to very small result sets, or (3) you're in a context (e.g., streaming) where replanning mid-query introduces latency you can't afford. In interviews, AQE is a sign of query maturity—demonstrating awareness of it shows you understand the gap between logical and physical planning.

## Practice

**Problem:** You're analyzing job postings. Write a query that joins `job_postings_fact` to a heavily filtered cohort of senior roles, then aggregates salary by location. The filter on job titles is very selective (removes 99% of rows), but the planner doesn't know this upfront.

```sql
SELECT 
  job_location,
  COUNT(*) as num_jobs,
  ROUND(AVG(salary_year_avg), 2) as avg_salary
FROM job_postings_fact jp
INNER JOIN (
  SELECT job_id 
  FROM job_postings_fact 
  WHERE job_title_short IN ('Senior Data Engineer', 'Senior Analyst')
    AND salary_year_avg > 150000
    AND job_posted_date >= '2024-01-01'
) senior_roles
ON jp.job_id = senior_roles.job_id
GROUP BY job_location
ORDER BY avg_salary DESC;
```

**Why AQE helps:** The subquery filter removes ~99% of rows. At plan time, the optimizer might choose sort-merge join (expecting millions). After the subquery runs, AQE observes the actual result set is ~10K rows and dynamically switches to broadcast join, avoiding a full shuffle of the larger `job_postings_fact` table.

## Notes

- **AQE is on by default in Spark 3.2+** (`spark.sql.adaptive.enabled = true`); verify it's enabled in your cluster config, especially in older/managed environments.
- **Skew handling:** AQE detects when one partition is much larger than others post-shuffle and splits it into smaller tasks, preventing straggler tasks from blocking the whole stage.
- **Join strategy coalescing:** AQE can downgrade expensive joins to broadcasts or nested-loop joins if runtime stats show it's safe—but only works if the smaller side fits in executor memory.
- **Partition coalescing:** After shuffle, if output partitions are small, AQE merges them to reduce task overhead and improve cache locality.
- **Interview angle:** Mention AQE when discussing query plan issues or slow joins on filtered tables; show you'd check `EXPLAIN (COST)` output and understand the difference between initial and final physical plans.
