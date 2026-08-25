---
date: 2026-08-25
phase: sql
topic: Statistical functions: percentile, mode and distribution analysis
---

# Statistical functions: percentile, mode and distribution analysis

*SQL for analytics and engineering*

## Concept

Percentiles, modes, and distribution analysis are essential for understanding data spread rather than just central tendency. While averages can mask skewed distributions, percentiles (25th, 50th, 75th) reveal where actual values cluster and help identify outliers. Mode shows the most frequent value—critical for categorical data or multimodal distributions. Together, these tools expose whether salary data is normally distributed, right-skewed (common in tech), or has distinct tiers of compensation.

In SQL, this matters because interview questions often ask "what's a typical salary?" and the answer depends on distribution shape. A $150k average might hide a bimodal distribution with clusters at $100k and $200k. Without percentiles, you miss salary bands; without mode, you can't identify the most common job title or location. Query performance also matters—window functions and approximate percentile calculations trade accuracy for speed on billion-row datasets.

## Practice

**Problem:** Find the distribution of salaries for Data Engineer roles: calculate the 25th, 50th, and 75th percentiles, the mode, and count how many jobs fall into each quartile band. Also determine if the distribution is left-skewed, normal, or right-skewed by comparing mean to median.

```sql
WITH salary_stats AS (
  SELECT
    salary_year_avg,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary_year_avg) 
      OVER () AS p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY salary_year_avg) 
      OVER () AS p50,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary_year_avg) 
      OVER () AS p75,
    AVG(salary_year_avg) OVER () AS mean_salary,
    MODE() WITHIN GROUP (ORDER BY salary_year_avg) OVER () AS mode_salary
  FROM job_postings_fact
  WHERE job_title_short = 'Data Engineer' AND salary_year_avg IS NOT NULL
),
quartile_assignment AS (
  SELECT
    salary_year_avg,
    p25, p50, p75, mean_salary, mode_salary,
    CASE
      WHEN salary_year_avg <= p25 THEN 'Q1'
      WHEN salary_year_avg <= p50 THEN 'Q2'
      WHEN salary_year_avg <= p75 THEN 'Q3'
      ELSE 'Q4'
    END AS quartile
  FROM salary_stats
)
SELECT
  (SELECT p25 FROM salary_stats LIMIT 1) AS percentile_25,
  (SELECT p50 FROM salary_stats LIMIT 1) AS percentile_50,
  (SELECT p75 FROM salary_stats LIMIT 1) AS percentile_75,
  (SELECT mode_salary FROM salary_stats LIMIT 1) AS mode_salary,
  (SELECT mean_salary FROM salary_stats LIMIT 1) AS mean_salary,
  ROUND((SELECT mean_salary FROM salary_stats LIMIT 1) - 
        (SELECT p50 FROM salary_stats LIMIT 1), 0) AS skew_indicator,
  quartile,
  COUNT(*) AS job_count
FROM quartile_assignment
GROUP BY quartile
ORDER BY quartile;
```

## Notes

- **PERCENTILE_CONT vs. PERCENTILE_DISC:** CONT interpolates between values (continuous), DISC returns an actual value. Use CONT for salary distributions, DISC for discrete counts.
- **MODE() limitations:** Many databases (Postgres, SQL Server) support MODE() with WITHIN GROUP, but some don't; fallback is `SELECT salary_year_avg FROM ... GROUP BY salary_year_avg ORDER BY COUNT(*) DESC LIMIT 1`.
- **Skewness detection:** If mean > median, right-skewed (high outliers); if mean < median, left-skewed (low outliers). Compare visually with quartile counts to confirm.
- **Window function cost:** Using OVER() without PARTITION BY forces full table scan; for large datasets, consider approximate percentiles (e.g., `APPROX_PERCENTILE` in BigQuery) or pre-aggregation.
- **Adjacent topics:** IQR (interquartile range = p75 − p25) for outlier detection, histogram binning for distribution shapes, and correlation analysis when comparing distributions across job titles or locations.
