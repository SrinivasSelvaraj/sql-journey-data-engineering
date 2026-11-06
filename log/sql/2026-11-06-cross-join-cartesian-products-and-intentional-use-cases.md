---
date: 2026-11-06
phase: sql
topic: Cross join: cartesian products and intentional use cases
---

# Cross join: cartesian products and intentional use cases

*SQL for analytics and engineering*

## Concept

A **cross join** (Cartesian product) returns every combination of rows from two tables—if table A has *m* rows and table B has *n* rows, the result has *m × n* rows. This is rarely the desired default join behavior; SQL engines will warn or fail on implicit cross joins. However, cross joins are intentional and necessary in specific analytical scenarios: generating all combinations of dimensions (e.g., every date paired with every product for a complete sales matrix), creating benchmark comparisons, or building exhaustive lookup tables. Without cross joins, you cannot solve problems requiring "all possible pairings"—you'd either miss combinations or overcomplicate the logic with window functions.

The performance cost scales quadratically, so cross joins are only safe when at least one input is small (typically < 10K rows). In interview contexts, mentioning cross join awareness signals you understand join semantics deeply and won't accidentally create one via missing join conditions. Always use explicit `CROSS JOIN` syntax rather than omitting the `ON` clause, which improves readability and prevents accidental bugs.

## Practice

**Problem:** You have a `job_postings_fact` table and need to generate a matrix showing, for each unique job title and work-from-home status combination, how many job postings exist. This requires pairing every unique title with every unique work-from-home value, then counting matches.

```sql
WITH titles AS (
  SELECT DISTINCT job_title_short
  FROM job_postings_fact
),
remote_options AS (
  SELECT DISTINCT job_work_from_home
  FROM job_postings_fact
),
all_combinations AS (
  SELECT t.job_title_short, r.job_work_from_home
  FROM titles t
  CROSS JOIN remote_options r
)
SELECT 
  ac.job_title_short,
  ac.job_work_from_home,
  COUNT(jp.job_id) AS posting_count
FROM all_combinations ac
LEFT JOIN job_postings_fact jp
  ON ac.job_title_short = jp.job_title_short
  AND ac.job_work_from_home = jp.job_work_from_home
GROUP BY ac.job_title_short, ac.job_work_from_home
ORDER BY ac.job_title_short, ac.job_work_from_home;
```

This cross join creates the complete dimension space; the subsequent left join fills in counts, showing zero where no postings exist—crucial for detecting missing combinations.

## Notes

- **Missing `ON` clause is not a cross join**—it's a syntax error in most SQL dialects. Always explicitly write `CROSS JOIN` to avoid ambiguity and accidental cartesian products.
- **Size check discipline**: Before writing a cross join, verify both inputs are small. Mentally compute the output row count; if it exceeds ~1M, reconsider the approach or add filters to one input first.
- **Connects to window functions and `GENERATE_SERIES`**: Problems that *seem* to need cross joins sometimes solve more efficiently with row generation functions or partitioned aggregations; evaluate both paths.
- **Common interview mistake**: Using cross join when a grouped `CASE` statement or pivot would suffice. Cross joins are for generating *structure*; use them intentionally, not as a default when joins feel complex.
- **Query plan awareness**: Explicitly name cross joins in your reasoning during code reviews; they're high-cost operations that should appear in EXPLAIN output as "Nested Loop" or "Cartesian Join" and should be justified aloud.
