---
date: 2026-10-10
phase: modelling
topic: Non-additive measures: ratios and percentages
---

# Non-additive measures: ratios and percentages

*Data modelling and warehousing*

## Concept

Non-additive measures are metrics that *cannot* be summed meaningfully across dimensions—ratios, percentages, averages, and rates. When you sum a ratio across multiple groups, you don't get a meaningful aggregate; you get mathematical nonsense. This matters enormously in schema design because if you store a pre-calculated percentage in a fact table, someone querying at a different grain (say, rolling up by region instead of department) will sum those percentages incorrectly and get wrong answers.

The solution is to store *component measures* (numerator and denominator separately) in the fact table, then calculate the ratio at query time. For example: store `remote_jobs_count` and `total_jobs_count` instead of `pct_remote`. This forces the schema to be self-documenting—users see the raw numbers and must consciously decide how to aggregate them—and prevents silent calculation errors.

Without this discipline, analysts create dashboards that appear correct at one drill-down level but become nonsensical when filtered or grouped differently. A "40% remote" figure meaningful at the company level becomes garbage when someone sums it across five business units.

## Practice

**Problem:** Your stakeholders want to know the percentage of remote-eligible jobs in each job category. You've been asked to design a `job_postings_fact` table so that anyone can query "what % of Data jobs allow remote work?" without asking you for clarification.

**Solution:**

```sql
-- Store components, not ratios
SELECT 
  job_title_short,
  COUNT(*) AS total_jobs,
  SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) AS remote_jobs,
  -- Calculate ratio only in SELECT, never store it
  ROUND(
    100.0 * SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) 
    / COUNT(*), 
    2
  ) AS pct_remote
FROM job_postings_fact
GROUP BY job_title_short
ORDER BY pct_remote DESC;
```

The fact table stores `job_work_from_home` (boolean) and `job_id` (grain identifier). Aggregations—counts and sums of counts—are additive; the percentage is computed *only* at query time after all grouping is complete.

## Notes

- **Average trap:** Storing `avg_salary` in a fact table is just as dangerous. Always store `salary_year_avg` (atomic value) and `COUNT`, then compute average on demand.
- **Grain matters:** If your fact table grain is one row per job posting, `SUM(job_work_from_home)` = remote count. If grain changes (e.g., one row per job per day), the same query breaks. Document grain explicitly.
- **Conformed dimensions:** Use the same `job_title_short` dimension consistently across all queries so "Data Engineer" means the same thing everywhere.
- **Slowly-changing dimension gotcha:** If job titles or remote eligibility can change retroactively, snapshot the fact table on `job_posted_date` to avoid recalculating history.
- **Related:** This connects to *additive vs. semi-additive measures*; revisit Kimball's dimensional model chapters on fact table grain and measure classification.
