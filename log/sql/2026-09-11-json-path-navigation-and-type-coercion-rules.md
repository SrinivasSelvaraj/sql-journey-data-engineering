---
date: 2026-09-11
phase: sql
topic: JSON path navigation and type coercion rules
---

# JSON path navigation and type coercion rules

*SQL for analytics and engineering*

## Concept

JSON path navigation uses bracket `[]` or dot notation to extract nested values from semi-structured data stored in JSON columns. Most SQL engines (PostgreSQL `jsonb`, Snowflake `VARIANT`, BigQuery `JSON`) require explicit path syntax; navigating incorrectly returns `NULL` rather than an error, making bugs silent. Type coercion rules determine what happens when you extract a JSON value and use it in a SQL context—a string `"123"` extracted from JSON won't automatically add to a number, and comparisons between JSON types and SQL types follow engine-specific rules that often surprise users under time pressure.

The practical stakes are high: a query that filters on `WHERE data->>'salary' > 100000` might fail silently if the field sometimes contains strings or nulls, or if you forget the `>>` (text extraction) operator and compare JSON to numbers. In analytics, you frequently receive denormalized event logs or API responses as JSON; navigating these structures correctly determines whether your aggregations include or exclude entire segments of data.

Understanding these rules prevents the common interview scenario where your query runs but produces mysteriously low row counts, or where a `JOIN` fails because one side has JSON type and the other has integer type.

## Practice

**Problem:** You receive a `job_postings_fact` table where `job_location` is stored as a JSON object: `{"city": "San Francisco", "state": "CA", "country": "USA"}`. Write a query that counts job postings by state, filtering for remote jobs with average salary > $100,000, and order by count descending.

```sql
SELECT
  job_location->>'state' AS state,
  COUNT(*) AS posting_count,
  ROUND(AVG(salary_year_avg)::numeric, 2) AS avg_salary
FROM job_postings_fact
WHERE
  job_work_from_home = TRUE
  AND salary_year_avg IS NOT NULL
  AND CAST(job_location->>'state' AS VARCHAR) IN ('CA', 'NY', 'TX', 'WA')
GROUP BY job_location->>'state'
HAVING AVG(salary_year_avg) > 100000
ORDER BY posting_count DESC;
```

Key moves: `->>'state'` extracts as text (not JSON); `salary_year_avg IS NOT NULL` guards against coercion errors; the `CAST` is defensive (some engines require it when comparing extracted JSON strings to literals); `HAVING` filters post-aggregation to avoid re-evaluating the average.

## Notes

- **Silent NULLs trap:** Incorrect JSON paths return `NULL` without warning. Test path syntax on sample rows first; a query returning zero rows often means navigation failed, not absence of data.
- **Operator confusion:** `->` returns JSON type; `->>` returns text. Using `->` in arithmetic (`WHERE data->'salary' > 100000`) fails or coerces unexpectedly. Pick the right operator for your next step.
- **Type coercion inconsistency:** PostgreSQL is strict; BigQuery and Snowflake auto-coerce in some contexts. Under interview pressure, assume you need explicit `CAST` or `EXTRACT` to be safe across engines.
- **GROUP BY path expressions:** Repeating `job_location->>'state'` in `GROUP BY` is verbose but necessary; aliasing in `SELECT` doesn't work for grouping. Some engines allow position, e.g., `GROUP BY 1`, but avoid it in interviews—be explicit.
- **Adjacent topics:** connects to schema design (why denormalize to JSON vs. normalize tables), query optimization (JSON extraction can't use indexes efficiently), and error handling (try-catch patterns for malformed JSON).
