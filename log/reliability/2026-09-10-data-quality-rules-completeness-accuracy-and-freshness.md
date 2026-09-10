---
date: 2026-09-10
phase: reliability
topic: Data quality rules: completeness, accuracy and freshness
---

# Data quality rules: completeness, accuracy and freshness

*Quality, reliability and the professional layer*

## Concept

Data quality rules define the boundaries between acceptable and unacceptable data. Completeness ensures required fields are populated; accuracy validates that values match their intended meaning and constraints; freshness guarantees data reflects current reality within an acceptable lag. Together, they form a contract: downstream consumers can assume data meeting these rules is trustworthy enough for decisions.

A pipeline owner differs from a pipeline builder precisely here. A builder delivers data; an owner guarantees it meets quality thresholds and surfaces failures before they reach dashboards or models. Without these rules, bad data propagates silently—a NULL salary_year_avg makes compensation analysis worthless, an accuracy drift of 2% in a pricing pipeline compounds into revenue leakage, and stale job postings convince job seekers to apply for closed roles.

Quality rules also scale responsibility. Early-stage projects can live with informal checks ("looks reasonable"). Mature systems require documented assertions, SLA definitions, and alerting infrastructure. The difference between "I hope the data is good" and "I guarantee the data is good" is exactly this formalization.

## Practice

**Problem:** Your job_postings_fact table is used by ML models to predict salary ranges and by recruiters to search active roles. You notice: (1) some rows have NULL salary_year_avg but were included in training, (2) job_posted_date shows values from 2099, (3) the table is updated daily but sometimes lags 48+ hours. Define completeness, accuracy, and freshness rules, then implement validation.

```sql
-- Define quality rules as a validation query
WITH data_quality_checks AS (
  SELECT
    -- Completeness: required fields must be non-null
    COUNTIF(job_id IS NULL) AS null_job_ids,
    COUNTIF(job_title_short IS NULL) AS null_titles,
    COUNTIF(job_posted_date IS NULL) AS null_posted_dates,
    
    -- Accuracy: values must fall within valid ranges
    COUNTIF(salary_year_avg < 20000 OR salary_year_avg > 500000) 
      AS out_of_range_salaries,
    COUNTIF(EXTRACT(YEAR FROM job_posted_date) > EXTRACT(YEAR FROM CURRENT_DATE())) 
      AS future_dated_postings,
    COUNTIF(job_work_from_home NOT IN (TRUE, FALSE)) 
      AS invalid_remote_flags,
    
    -- Freshness: age of most recent record
    DATE_DIFF(CURRENT_DATE(), MAX(job_posted_date), DAY) 
      AS max_days_since_latest_post,
    
    -- Overall row count for context
    COUNT(*) AS total_rows
  FROM job_postings_fact
)
SELECT
  *,
  -- Pass/fail: adjust thresholds based on SLA
  CASE 
    WHEN null_job_ids > 0 THEN 'FAIL: Missing job_ids'
    WHEN null_titles > total_rows * 0.01 THEN 'FAIL: >1% missing titles'
    WHEN out_of_range_salaries > total_rows * 0.05 THEN 'FAIL: >5% invalid salaries'
    WHEN future_dated_postings > 0 THEN 'FAIL: Future-dated postings detected'
    WHEN max_days_since_latest_post > 2 THEN 'FAIL: Data stale >48 hours'
    ELSE 'PASS'
  END AS quality_status
FROM data_quality_checks;
```

## Notes

- **Threshold selection is a business choice, not a technical one.** A 5% tolerance for salary outliers might be acceptable for exploration but forbidden for payroll. Own the conversation with stakeholders about what "good enough" means.

- **Completeness and accuracy are not binary.** NULL fields may be genuinely unknown (acceptable) or unrecorded (unacceptable). Salary outliers might reflect executive roles or data errors. Build categorical logic, not just row filters.

- **Freshness interacts with source systems.** If your upstream API publishes jobs in batches every 6 hours, a 48-hour SLA is unrealistic. Understand and document the natural rhythm of your data.

- **These rules must be monitored continuously, not just at load time.** Implement logging, alerting, and a data quality dashboard. A rule that isn't monitored is a rule that will fail undetected.

- **Adjacent: reconciliation (volume/hash checks), schema validation (type mismatches), referential integrity (foreign keys), and observability.** Quality rules are the foundation; observability lets you detect when they break.
