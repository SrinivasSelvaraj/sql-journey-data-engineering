---
date: 2026-08-26
phase: sql
topic: Sampling: TABLESAMPLE and stratified sampling for large tables
---

# Sampling: TABLESAMPLE and stratified sampling for large tables

*SQL for analytics and engineering*

## Concept

**TABLESAMPLE** is a SQL clause that retrieves a random subset of rows from a table without scanning the entire dataset. Most databases (PostgreSQL, SQL Server, Snowflake) support `TABLESAMPLE BERNOULLI` (row-level random selection) or `TABLESAMPLE SYSTEM` (block-level sampling, faster but less uniform). This is critical when analyzing multi-billion-row tables where a full scan is prohibitively expensive—you get fast approximate statistics with controlled randomness rather than biased samples of early rows.

**Stratified sampling** deliberately splits the population into groups (strata) first, then samples uniformly within each group. This is essential when you need representative samples across categorical dimensions (e.g., equal representation of remote vs. on-site roles). TABLESAMPLE alone gives no guarantee that rare categories appear in your sample; stratified sampling ensures they do, making insights valid across all business segments.

Without sampling, ad-hoc analytics on 1TB+ tables timeout or consume excessive compute. Without stratification, your sample misses tail categories entirely, leading to invalid conclusions about salary ranges for niche job titles or underrepresented locations.

## Practice

**Problem:** You need a quick statistical summary of salary_year_avg across job_title_short categories from a 500M-row job_postings_fact table. A full scan takes 8 minutes. Build a stratified sample that pulls 1% of rows *per job title* to ensure every job title is represented, then compute mean and percentiles.

```sql
-- Stratified sample: 1% per job_title_short
WITH stratified_sample AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
    AND RAND() < 0.01  -- 1% row-level probability per group
  QUALIFY ROW_NUMBER() OVER (PARTITION BY job_title_short ORDER BY RAND()) 
           <= CEIL(COUNT(*) OVER (PARTITION BY job_title_short) * 0.01)
)
SELECT 
  job_title_short,
  COUNT(*) AS sample_size,
  ROUND(AVG(salary_year_avg), 0) AS mean_salary,
  ROUND(PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary_year_avg), 0) AS p25,
  ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary_year_avg), 0) AS p75
FROM stratified_sample
GROUP BY job_title_short
HAVING COUNT(*) >= 10
ORDER BY mean_salary DESC;
```

*Alternative for Snowflake/PostgreSQL with native TABLESAMPLE:*
```sql
SELECT 
  job_title_short,
  COUNT(*) AS sample_size,
  ROUND(AVG(salary_year_avg), 0) AS mean_salary
FROM job_postings_fact TABLESAMPLE BERNOULLI (1)
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short
HAVING COUNT(*) >= 50;
```
*(Note: TABLESAMPLE is faster but may miss rare strata; add explicit stratification if tail categories matter.)*

## Notes

- **TABLESAMPLE BERNOULLI vs. SYSTEM:** Bernoulli reads entire blocks but decides per-row (uniform, slower); SYSTEM skips blocks (faster, but can bias toward clustered data). Use SYSTEM for rough ETL profiling, BERNOULLI for analytical accuracy.

- **Stratification requires explicit partitioning logic:** TABLESAMPLE alone won't ensure every category is represented. Use `PARTITION BY` + `ROW_NUMBER()` or a two-step CTE to enforce minimum sample size per strata.

- **Sampling doesn't eliminate bias—it trades precision for speed.** Always document that results are approximate and indicate confidence intervals or margin of error when presenting to stakeholders.

- **Adjacent topics:** Connects to query optimization (identifying expensive full scans via EXPLAIN), approximate query processing (HyperLogLog cardinality estimation), and hypothesis testing (ensuring sample size is statistically valid for your confidence level).

- **Common mistake:** Using `LIMIT` or `WHERE job_posted_date = CURRENT_DATE` instead of random sampling—this introduces selection bias. Always use `RAND()` or TABLESAMPLE for unbiased samples.
