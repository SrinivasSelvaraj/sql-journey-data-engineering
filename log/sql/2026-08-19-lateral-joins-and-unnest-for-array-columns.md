---
date: 2026-08-19
phase: sql
topic: LATERAL joins and UNNEST for array columns
---

# LATERAL joins and UNNEST for array columns

*SQL for analytics and engineering*

## Concept

**LATERAL joins** and **UNNEST** solve a critical problem: extracting and filtering on nested array/list columns that exist within a single row. Without them, you either flatten data incorrectly (creating cartesian products) or cannot filter at all on array elements. LATERAL allows a subquery on the right side to reference columns from the left, making it possible to unnest an array and apply row-specific logic in one pass.

In analytics, this matters when source tables contain denormalized arrays—tags on a job posting, skills required, company certifications. A naive approach (selecting the array directly) loses granularity. A naive join (unnesting without LATERAL) duplicates left-side aggregates. LATERAL + UNNEST gives you the ability to explode arrays into rows *per source row*, then filter, aggregate, or rank within that scope, without duplication.

The query breaks without LATERAL when you need context from the outer row inside the unnested subquery. Many SQL dialects require explicit LATERAL syntax (BigQuery, Postgres, Snowflake); others (DuckDB, some versions of Snowflake) allow implicit lateral behavior. Performance matters: unnesting filtered arrays inside LATERAL is faster than unnesting first, then filtering.

## Practice

**Problem:** For each job posting, list the top 2 most common job locations where that job title has been posted. You have a denormalized table where `job_location` is stored as an ARRAY type (e.g., `['New York, NY', 'San Francisco, CA', 'New York, NY']`).

```sql
SELECT
  job_id,
  job_title_short,
  location,
  location_count,
  ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY location_count DESC) AS rank
FROM (
  SELECT
    j.job_id,
    j.job_title_short,
    loc AS location,
    COUNT(*) AS location_count
  FROM job_postings_fact j
  LATERAL FLATTEN(INPUT => j.job_location) f
  GROUP BY j.job_id, j.job_title_short, loc
)
QUALIFY rank <= 2
ORDER BY job_id, rank;
```

*(Note: Syntax varies by dialect—Snowflake uses FLATTEN; Postgres/BigQuery use UNNEST. Replace FLATTEN with UNNEST in most other engines.)*

## Notes

- **Mistake: forgetting LATERAL** — writing `FROM table1 JOIN UNNEST(array_col)` without LATERAL causes the unnest to lose context of the row it came from; use `FROM table1 LATERAL JOIN UNNEST(array_col)` or equivalent.
- **Mistake: aggregating before unnesting** — if you aggregate the outer table first, you lose the ability to unnest meaningfully; always unnest *inside* the subquery or use LATERAL to preserve row identity.
- **Related: window functions after unnest** — QUALIFY and ROW_NUMBER() often follow LATERAL unnest to rank or filter within groups; this combination is powerful for "top N per group" problems.
- **Performance: push filters into LATERAL subquery** — filter array elements inside the LATERAL block, not after, to reduce rows early; `LATERAL UNNEST(ARRAY_AGG(IF(condition, elem, NULL))) IGNORE NULLS` can be faster than unnesting then filtering.
- **Dialect awareness** — BigQuery (`UNNEST`), Snowflake (`FLATTEN`), Postgres (`UNNEST`), and DuckDB (`UNNEST`) have slightly different syntax and null-handling; always test on your target platform.
