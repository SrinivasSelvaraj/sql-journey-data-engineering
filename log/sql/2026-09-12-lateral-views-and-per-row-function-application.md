---
date: 2026-09-12
phase: sql
topic: Lateral views and per-row function application
---

# Lateral views and per-row function application

*SQL for analytics and engineering*

## Concept

A lateral view (or LATERAL JOIN in standard SQL) applies a table-generating function to each row of an input table, then flattens the results back into a single output. This is essential when a function returns multiple rows per input row—without it, you'd either lose data or resort to inefficient workarounds. Common scenarios include exploding arrays/maps, parsing delimited strings, generating date ranges, or applying user-defined functions that output variable cardinality.

The key difference from a regular JOIN: a lateral view can reference columns from the left-hand table in the function call on the right, making each invocation row-specific. Without this capability, you cannot cleanly separate one-to-many expansions from filtering or aggregation logic, leading to either incorrect results (duplicates, missing rows) or performance cliffs (self-joins, window functions as workarounds).

In Spark SQL (and Hive), the syntax is `LATERAL VIEW [OUTER] explode(array_col) alias_table AS alias_col`. The OUTER keyword preserves rows where the function returns zero results (like a left outer join). Understanding when to use LATERAL VIEW vs. window functions vs. simple JOINs is a marker of query maturity.

## Practice

**Problem:** Given `job_postings_fact`, assume `job_location` contains pipe-delimited locations (e.g., "New York|San Francisco|Remote"). Expand each posting into one row per location, then count how many postings are available in each location.

```sql
SELECT
  location,
  COUNT(DISTINCT job_id) AS posting_count
FROM job_postings_fact
LATERAL VIEW explode(split(job_location, '\\|')) locations AS location
GROUP BY location
ORDER BY posting_count DESC;
```

This lateral view splits the pipe-delimited string into an array, then explodes it so each location becomes its own row. The grouping and count then operate on the expanded set. Without LATERAL VIEW, you'd need a self-join or UDF workaround that would be harder to read and likely slower.

## Notes

- **OUTER vs. inner:** `LATERAL VIEW OUTER explode(...)` keeps rows where the function returns empty (e.g., NULL arrays). Omitting OUTER filters them out—choose based on whether missing data should be preserved.
- **Common pitfall:** Forgetting the alias after the function (`AS locations AS location`). The first alias names the virtual table, the second names the column(s).
- **Adjacent topics:** Window functions (ROW_NUMBER, DENSE_RANK) handle per-row computation without expansion; use lateral views only when cardinality changes. Also related: collect_list + explode for the inverse operation (grouping into arrays).
- **Performance consideration:** Lateral views can multiply row count significantly; filter early (WHERE before the LATERAL VIEW) when possible, and avoid nesting multiple lateral views without testing the plan.
- **Revisit:** The difference between SQL standard LATERAL and Spark/Hive LATERAL VIEW syntax; some systems use CROSS APPLY or UNNEST instead. Always check documentation for your platform.
