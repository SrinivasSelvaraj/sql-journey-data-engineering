---
date: 2026-10-03
phase: sql
topic: Common table expressions: recursive CTE performance patterns
---

# Common table expressions: recursive CTE performance patterns

*SQL for analytics and engineering*

## Concept

Recursive CTEs enable hierarchical or iterative traversals—common in org charts, bill-of-materials, or path-finding problems—but they can become bottlenecks if the recursion depth is large or termination conditions are loose. A recursive CTE has two parts: an anchor query (base case) and a recursive member (inductive step) that joins the previous iteration's result set back to a source table. Performance degrades when:
- The recursive member produces exponentially more rows per iteration (e.g., missing `WHERE` filters or `UNION ALL` cardinality explosion)
- Recursion depth is unbounded or unexpectedly deep, forcing the engine to materialize intermediate result sets
- No index supports the join condition in the recursive step

Without explicit termination logic or depth limits, unbounded recursion can exhaust memory or hit execution timeouts. The key to performant recursive CTEs is filtering aggressively in the anchor and recursive member, using `WHERE` clauses tied to indexed columns, and setting a reasonable `MAXRECURSION` hint when the depth is known.

## Practice

**Problem:** Given `job_postings_fact`, find all job postings posted within 7 days of the earliest posting for each `job_title_short`. Use a recursive CTE to iteratively build a window of related postings, starting from the earliest, then stopping once you exceed the 7-day window.

```sql
WITH RECURSIVE date_window AS (
  -- Anchor: find the earliest posting date per job title
  SELECT
    job_title_short,
    job_posted_date AS window_start_date,
    job_posted_date AS current_date,
    1 AS iteration
  FROM job_postings_fact
  WHERE (job_title_short, job_posted_date) IN (
    SELECT job_title_short, MIN(job_posted_date)
    FROM job_postings_fact
    GROUP BY job_title_short
  )

  UNION ALL

  -- Recursive member: expand the window by 1 day
  SELECT
    dw.job_title_short,
    dw.window_start_date,
    DATEADD(DAY, 1, dw.current_date) AS current_date,
    dw.iteration + 1
  FROM date_window dw
  WHERE DATEDIFF(DAY, dw.window_start_date, dw.current_date) < 7
    AND dw.iteration < 7  -- explicit termination
)
SELECT DISTINCT
  jp.job_id,
  jp.job_title_short,
  jp.job_posted_date,
  jp.salary_year_avg
FROM job_postings_fact jp
INNER JOIN date_window dw
  ON jp.job_title_short = dw.job_title_short
  AND jp.job_posted_date >= dw.window_start_date
  AND jp.job_posted_date <= dw.current_date
ORDER BY jp.job_title_short, jp.job_posted_date;
```

## Notes

- **Cardinality explosion:** Every iteration of the recursive member joins back to the source table; without tight `WHERE` predicates, row counts grow exponentially. Always filter on indexed columns in the recursive step.
- **Depth limits matter:** Set `OPTION (MAXRECURSION N)` or equivalent (or explicitly terminate in the `WHERE` clause) to prevent runaway queries; 100–1000 iterations is reasonable for most business problems.
- **Index strategy:** Ensure indexes cover the join columns and `WHERE` predicates in the recursive member; a missing index on `(job_title_short, job_posted_date)` will force table scans at each iteration.
- **Adjacent: window functions & hierarchical queries:** Recursive CTEs solve problems that window functions (e.g., `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)`) cannot; they also pair naturally with directed acyclic graphs (DAGs) like org hierarchies or supply chains.
- **Test with small datasets first:** Write the query against a filtered or development dataset to verify termination logic before running on production; a single missing condition can lock up the database.
