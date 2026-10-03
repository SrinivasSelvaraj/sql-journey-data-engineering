---
date: 2026-10-03
phase: sql
topic: Aggregation algorithms: sort vs hash aggregate trade-offs
---

# Aggregation algorithms: sort vs hash aggregate trade-offs

*SQL for analytics and engineering*

## Concept

Aggregation in SQL can be executed two fundamentally different ways: **sort aggregate** (group-by-sort) and **hash aggregate**. Sort aggregate first sorts the input by grouping columns, then scans linearly to combine rows; hash aggregate builds an in-memory hash table of group keys and accumulates values into buckets. The choice between them depends on data volume, memory availability, and whether the result must be ordered.

Sort aggregate excels when data is already sorted (or can be cheaply sorted via an index), when memory is constrained, or when output must be pre-sorted—it has predictable memory usage and streams results incrementally. Hash aggregate dominates when grouping cardinality is moderate, memory is abundant, and sort order isn't required—it avoids expensive disk sorts and typically outperforms on unsorted large datasets. Neither is universally "better"; the optimizer must weigh CPU cost (sorting is O(n log n)), I/O cost (sort may spill to disk), and memory pressure (hash table growth).

This matters in interviews because you'll see slow GROUP BY queries in production and need to reason about why. A query that groups by 50M unique values on a server with 16GB RAM will either spill dramatically (hash) or take forever sorting (sort). Understanding which algorithm is running—and how to hint or restructure to prefer one—separates competent engineers from those who blindly write GROUP BY and hope.

## Practice

**Problem:** You're analyzing job posting trends. Find the average salary and count of postings per job title, but only for remote jobs posted in 2024. Sort the output by count descending, and limit to titles with 10+ postings. Write this query and explain which aggregation strategy you'd expect the optimizer to choose and why.

```sql
SELECT 
  job_title_short,
  COUNT(*) AS posting_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND YEAR(job_posted_date) = 2024
  AND salary_year_avg IS NOT NULL
GROUP BY job_title_short
HAVING COUNT(*) >= 10
ORDER BY posting_count DESC;
```

**Why hash aggregate likely wins here:** After filtering, you're grouping by job_title_short (probably 20–200 unique values). A hash aggregate builds a small in-memory table, scans filtered rows once, and streams results to the ORDER BY. Sort aggregate would unnecessarily sort thousands of rows by title string. Memory usage is minimal because cardinality is low. If job_title_short had a composite index with job_posted_date, sort aggregate might be competitive—but that's unlikely to exist.

## Notes

- **Memory spillover trap:** Hash aggregate on a high-cardinality grouping (e.g., GROUP BY user_id on 100M users) will spill to disk and become slower than sort. Always check HAVING or use a pre-aggregation layer (e.g., dimensional rollups) to reduce cardinality first.

- **Index-backed sorts are free:** If a composite index exists on (job_work_from_home, job_posted_date, job_title_short), the optimizer may scan it in order, making sort aggregate nearly free—query planners love this path.

- **DISTINCT vs GROUP BY:** DISTINCT often uses the same algorithms; hash aggregate is usually faster for DISTINCT unless the result fits in L3 cache and sort order is beneficial downstream.

- **Window functions and aggregates:** Window functions (ROW_NUMBER, RANK, SUM OVER) often force a sort pass anyway; GROUP BY + ORDER BY can be cheaper or more expensive than a single window partition depending on the output requirement.

- **Interview checklist:** Always ask "how many groups?" and "is the result already sorted by an index?" before choosing a strategy. Run EXPLAIN and look for "Hash Aggregate" vs "Sort" and memory estimates; if memory >> available RAM, push for a two-stage aggregation.
