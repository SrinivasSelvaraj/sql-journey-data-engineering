---
date: 2026-10-23
phase: sql
topic: String aggregation and array functions efficiency
---

# String aggregation and array functions efficiency

*SQL for analytics and engineering*

## Concept

String aggregation and array functions allow you to combine multiple row values into a single string or array, critical when you need to denormalize grouped data for reporting or downstream consumption. In SQL, `STRING_AGG()` (PostgreSQL/BigQuery), `GROUP_CONCAT()` (MySQL), or `LISTAGG()` (Oracle) collapse rows within a group; array functions like `ARRAY_AGG()` do the same but preserve type information and enable further array operations. These operations matter because without them, you either repeat expensive joins or lose information during GROUP BY—but they *cost* if misused: aggregating millions of long strings per group can explode memory, and sorting within the aggregate (ORDER BY inside the function) adds CPU overhead that scales poorly.

The key efficiency trade-off is *when to aggregate vs. when to leave normalized*. Aggregating job titles into a single row per company saves network bandwidth and makes reporting simpler, but if you then need to filter or rank by individual titles, you've locked yourself out of efficient indexing. Query planners also struggle to estimate aggregation output size, leading to poor memory allocation and spilled-to-disk operations on large groups.

## Practice

**Problem:** For each job location, list the top 3 most common job titles (by frequency) and the count of remote-eligible positions. Return location, aggregated titles, and remote count in a single row per location.

```sql
WITH title_counts AS (
  SELECT 
    job_location,
    job_title_short,
    COUNT(*) AS title_freq,
    SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) AS remote_count,
    ROW_NUMBER() OVER (PARTITION BY job_location ORDER BY COUNT(*) DESC) AS rank
  FROM job_postings_fact
  GROUP BY job_location, job_title_short
)
SELECT 
  job_location,
  STRING_AGG(job_title_short, ' | ' ORDER BY title_freq DESC) AS top_3_titles,
  SUM(remote_count) AS total_remote_positions
FROM title_counts
WHERE rank <= 3
GROUP BY job_location
ORDER BY total_remote_positions DESC;
```

## Notes

- **ORDER BY inside aggregate is expensive:** `STRING_AGG(col, ',' ORDER BY col2 DESC)` forces a sort per group before concatenation; only use if order is semantically required, not cosmetic.
- **Memory spillover on large groups:** If one location has 100k job postings and you aggregate all titles, you're building a massive string in memory. Limit with WHERE/rank windows *before* aggregation to stay within working memory.
- **Type safety with arrays:** `ARRAY_AGG()` preserves nullability and type, letting you use `ARRAY_LENGTH()` or `ARRAY_CONTAINS()` downstream; strings lose this metadata, so choose based on downstream consumption.
- **Connects to window functions:** You often need `ROW_NUMBER() OVER (PARTITION BY ...)` *before* aggregating to filter rows per group (top-N per group pattern).
- **Index-unfriendly:** Queries with string aggregation rarely benefit from indexes on the aggregated column; they force full table scans or large range scans, so push filters earlier in CTEs.
