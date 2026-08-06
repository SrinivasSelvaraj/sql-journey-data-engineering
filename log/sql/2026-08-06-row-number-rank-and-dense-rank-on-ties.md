---
date: 2026-08-06
phase: sql
topic: ROW_NUMBER, RANK and DENSE_RANK on ties
---

# ROW_NUMBER, RANK and DENSE_RANK on ties

*SQL for analytics and engineering*

## Concept

**ROW_NUMBER**, **RANK**, and **DENSE_RANK** are window functions that assign numeric positions to rows within a partition, but differ critically in how they handle ties. ROW_NUMBER assigns a unique integer to every row regardless of ties—if three rows tie for second place, they receive positions 2, 3, and 4. RANK and DENSE_RANK both respect ties: RANK skips positions (2, 2, 2, 5), while DENSE_RANK does not (2, 2, 2, 3). Choosing the wrong function causes incorrect filtering or ranking logic, especially when you need to identify top-N records or analyze leaderboards where tied values should have equal rank.

The practical consequence appears when filtering results. If you use `WHERE ROW_NUMBER() = 1` you get exactly one row per partition even if multiple rows are tied for best. If you need all tied rows (e.g., "all employees with the highest salary in their department"), DENSE_RANK or RANK is necessary. Similarly, RANK is useful for competition-style rankings where a tie affects subsequent positions; DENSE_RANK is better for ordinal "tier" assignments that don't skip numbers.

## Practice

**Problem:** For each job title, identify which salary tier each posting falls into—top 25%, 25–50%, 50–75%, or bottom 25%. Use NTILE instead, or rank salaries within each title and categorize by quartile using DENSE_RANK. Return job_id, job_title_short, salary_year_avg, and tier label.

```sql
WITH ranked_salaries AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    DENSE_RANK() OVER (
      PARTITION BY job_title_short 
      ORDER BY salary_year_avg DESC
    ) AS rank_desc,
    COUNT(*) OVER (PARTITION BY job_title_short) AS total_count
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
)
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  CASE
    WHEN rank_desc <= CEIL(total_count * 0.25) THEN 'Top 25%'
    WHEN rank_desc <= CEIL(total_count * 0.50) THEN '25–50%'
    WHEN rank_desc <= CEIL(total_count * 0.75) THEN '50–75%'
    ELSE 'Bottom 25%'
  END AS salary_tier
FROM ranked_salaries
ORDER BY job_title_short, rank_desc;
```

## Notes

- **ROW_NUMBER() with ties:** Often a hidden bug—using it to get "top earner" silently drops tied rows. Always verify your intent.
- **RANK vs DENSE_RANK trade-off:** RANK for sports/competition (position matters); DENSE_RANK for categorical tiers (consecutive labels).
- **NTILE():** A third option for quartile/decile binning; cleaner than manual CASE logic when you want equal-sized buckets rather than value-based ranks.
- **Order of operations:** The `ORDER BY` clause in the window function is what determines ties, not the data distribution—identical values always tie, regardless of insertion order.
- **Filtering after ranking:** Use a CTE or subquery to compute ranks first, then filter—avoid putting window functions in WHERE clauses directly (syntax error in most databases).
