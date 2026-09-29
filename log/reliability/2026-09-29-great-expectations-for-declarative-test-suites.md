---
date: 2026-09-29
phase: reliability
topic: Great Expectations for declarative test suites
---

# Great Expectations for declarative test suites

*Quality, reliability and the professional layer*

## Concept

Great Expectations is a Python framework for defining data quality rules declaratively—as code that describes *what should be true* about your data, not *how to check it*. Instead of writing ad-hoc validation logic scattered across your pipeline, you codify expectations (column nullability, value ranges, regex patterns, statistical properties) in a suite that runs automatically and produces rich validation reports.

This matters when you transition from "does this pipeline run?" to "can I trust the output?" A pipeline may complete successfully while producing silent data corruption: nullable salary fields, job titles with unexpected characters, locations that don't match a gazetteer, or date anomalies. Without declarative tests, these slip downstream into dashboards and models. Great Expectations forces you to name your assumptions upfront, making data contracts explicit and violations immediately visible.

Without it, data quality issues hide until they affect stakeholders. You get blamed for "bad data" you didn't validate. With it, you own the quality layer professionally—you can say "we tested for X, Y, Z" and provide evidence. It's the difference between a pipeline that happens to work and a data system you're accountable for.

## Practice

**Problem:** Your job_postings_fact table ingests job data daily. You need to ensure salary_year_avg is populated and reasonable, job_posted_date never goes backward, job_work_from_home is always a valid boolean, and job_location is never empty. Currently, bad records pass through silently.

```sql
-- Great Expectations checkpoint (Python, but shown conceptually in SQL validation style)
-- In practice, you'd define this in a Great Expectations suite YAML or Python

SELECT 
  COUNT(*) as total_records,
  COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) as null_salary,
  COUNT(CASE WHEN salary_year_avg < 20000 OR salary_year_avg > 500000 THEN 1 END) as out_of_range_salary,
  COUNT(CASE WHEN job_work_from_home NOT IN (TRUE, FALSE) THEN 1 END) as invalid_boolean,
  COUNT(CASE WHEN job_location IS NULL OR job_location = '' THEN 1 END) as null_location,
  MIN(job_posted_date) as earliest_date,
  MAX(job_posted_date) as latest_date
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 day';

-- In Great Expectations Python:
-- suite.add_expectation(ExpectColumnValuesToNotBeNull(column='job_location'))
-- suite.add_expectation(ExpectColumnValuesToBeBetween(column='salary_year_avg', min_value=20000, max_value=500000))
-- suite.add_expectation(ExpectColumnValuesToBeInSet(column='job_work_from_home', value_set=[True, False]))
-- suite.run_validation_operator('action_list_operator')
```

## Notes

- **Common mistake:** Writing expectations so loose they never fail. "salary can be anything" defeats the purpose. Calibrate thresholds on clean data first, then tighten incrementally.
- **Silent success trap:** A validation suite that runs but isn't tied to pipeline gates. If failures don't stop the load or alert, you've built a report, not a safeguard. Wire it to your orchestrator (Airflow, dbt, Dagster).
- **Schema validation is first:** Before statistical expectations, ensure columns exist, have correct types, and are present. Great Expectations handles this natively; pair it with dbt contracts for extra rigor.
- **Connects to:** Data catalogs (document what you're validating and why), observability (log expectation results alongside pipeline runs), and SLOs (frame quality as a service commitment).
- **Revisit:** The difference between point-in-time validation (does today's load look right?) and drift detection (has this metric shifted from baseline?). Great Expectations handles both; choose your approach based on data maturity.
