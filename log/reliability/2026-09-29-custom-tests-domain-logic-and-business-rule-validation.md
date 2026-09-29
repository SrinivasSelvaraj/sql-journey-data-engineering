---
date: 2026-09-29
phase: reliability
topic: Custom tests: domain logic and business rule validation
---

# Custom tests: domain logic and business rule validation

*Quality, reliability and the professional layer*

## Concept

Custom tests validate the *semantic correctness* of data against business rules—not just schema validity or null counts, but whether values make logical sense together. A salary of $15,000 for a senior role, a remote job listed in 30 countries simultaneously, or a job posted before your company existed are all technically valid rows that fail business logic.

These tests are where you move from *technical reliability* (does the pipeline run?) to *operational trustworthiness* (can I confidently make a decision with this data?). They're the difference between a self-healing pipeline and one that silently produces garbage. Without them, stakeholders discover bad data in their analysis or—worse—in decisions already made.

Custom tests live downstream of dbt's built-in assertions and upstream of the business team's skepticism. They're your contract with the data consumer, encoded as code.

## Practice

**Problem:** Job postings with extremely low salaries (below minimum wage) or impossibly high values should flag as anomalies. Remote positions shouldn't list thousands of job locations. Posts dated in the future are data entry errors.

```sql
-- dbt test: assert_reasonable_job_economics.sql
select job_id
from {{ ref('job_postings_fact') }}
where 
  -- salary below $15k/year or above $500k/year for the dataset
  (salary_year_avg < 15000 or salary_year_avg > 500000)
  -- remote jobs with multiple locations listed (data quality red flag)
  or (job_work_from_home = true and job_location like '%,%')
  -- posted date in future
  or job_posted_date > current_date
```

Attach this to your model with `tests:` in YAML; dbt will fail the run if violations exist, triggering investigation before bad data reaches dashboards.

## Notes

- **Confuse domain tests with generic tests.** `not_null` catches missing data; custom tests catch *wrong* data. Both needed, different purposes.
- **Hard-code thresholds carefully.** $500k cap works now but may break in 5 years or different job markets. Consider parameterizing against historical percentiles or external config.
- **Connect to data contracts and SLAs.** Custom tests formalize what "good" means; they're the operational expression of agreements with downstream teams.
- **Revisit: dbt singular tests, Great Expectations for more complex rule engines, schema validation as a separate layer, and how to alert vs. block.**
- **Common mistake:** Writing tests *after* data problems occur rather than *before* shipping the dataset. Bake validation into your development cycle.
