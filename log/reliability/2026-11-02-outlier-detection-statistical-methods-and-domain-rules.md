---
date: 2026-11-02
phase: reliability
topic: Outlier detection: statistical methods and domain rules
---

# Outlier detection: statistical methods and domain rules

*Quality, reliability and the professional layer*

## Concept

Outlier detection separates genuine data anomalies from errors, fraud, or edge cases that corrupt downstream analysis and model training. Statistical methods (z-score, IQR, isolation forests) find points that deviate from expected distributions; domain rules (business logic) catch impossibilities—negative salaries, future dates, impossible combinations. Without outlier detection, a single mistyped salary of $999,999,999 can skew aggregations, break ML models, and pollute reports that executives make decisions from. This is where pipeline builders become stewards: ownership means catching the $0 salary that's actually a data entry error, not a valid minimum wage edge case.

The professional layer distinguishes between flagging outliers (detection) and deciding what to do with them (handling). You might reject them, quarantine them for review, impute them, or log them as intentional exceptions. The choice depends on domain knowledge—are you building a resume salary scraper where extreme values indicate web scraping failures, or a dataset of executive compensation where $10M is real? Documenting your decision criteria makes your pipeline trustworthy and auditable.

## Practice

**Problem:** Your job_postings_fact table has salary anomalies: some entries show $0, others show $5,000,000. Marketing wants average salary by location, but these outliers are distorting results. You need to detect and handle outliers using both statistical thresholds and business rules.

```sql
WITH salary_stats AS (
  SELECT
    job_location,
    COUNT(*) as count,
    AVG(salary_year_avg) as mean_sal,
    STDDEV(salary_year_avg) as stddev_sal,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY salary_year_avg) as q1,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY salary_year_avg) as q3
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
  GROUP BY job_location
),
outlier_flags AS (
  SELECT
    j.job_id,
    j.job_location,
    j.salary_year_avg,
    CASE
      WHEN j.salary_year_avg <= 0 THEN 'invalid_domain_rule'
      WHEN j.salary_year_avg > 2000000 THEN 'invalid_domain_rule'
      WHEN j.salary_year_avg < (s.q1 - 1.5 * (s.q3 - s.q1)) 
        OR j.salary_year_avg > (s.q3 + 1.5 * (s.q3 - s.q1)) THEN 'statistical_outlier'
      ELSE 'valid'
    END as outlier_status
  FROM job_postings_fact j
  LEFT JOIN salary_stats s ON j.job_location = s.job_location
  WHERE j.salary_year_avg IS NOT NULL
)
SELECT
  job_location,
  outlier_status,
  COUNT(*) as count,
  AVG(CASE WHEN outlier_status = 'valid' THEN salary_year_avg END) as clean_avg_salary
FROM outlier_flags
GROUP BY job_location, outlier_status
ORDER BY job_location, outlier_status;
```

## Notes

- **Confuse detection with action:** Flagging an outlier is not the same as deleting it. Always log outliers separately before filtering; you may need them for audit trails or later investigation.
- **Domain rules beat statistics:** A salary of $0 might be statistically normal in a dataset of unpaid internships, but it's a domain error (missing data). Always layer business logic on top of statistical thresholds.
- **Connected topics:** This feeds into data validation frameworks (Great Expectations, dbt tests), data quality scorecards, and incident response—when an outlier surge indicates upstream pipeline failure.
- **Revisit seasonality and cohorts:** An outlier in one job_location might be normal in another (NYC vs rural). Always stratify before computing stats; global thresholds hide local truths.
- **Document your decisions:** Write a data dictionary entry for each rule—why $2M is the ceiling, when you'd accept exceptions, who approves overrides. This is how you build trust with stakeholders and new team members.
