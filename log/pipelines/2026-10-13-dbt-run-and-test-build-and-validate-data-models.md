---
date: 2026-10-13
phase: pipelines
topic: dbt run and test: build and validate data models
---

# dbt run and test: build and validate data models

*Pipelines and orchestration*

## Concept

**dbt run** executes your SQL models in dependency order, transforming raw data into curated fact and dimension tables. **dbt test** validates assumptions about those models—checking for nulls, uniqueness, referential integrity, and custom business logic—without these tests, bad data silently corrupts downstream analytics and reports. Together they form a feedback loop: run models, test them immediately, fail fast if assumptions break, and make debugging obvious rather than discovering data quality issues weeks later in a dashboard.

The critical moment this matters is when you have multiple models depending on each other. If your `job_postings_fact` depends on upstream `stg_job_postings`, and that staging model suddenly has duplicate job_ids, dbt test catches it before aggregations or joins produce nonsense. Without tests, you ship incorrect analysis and spend days tracing why revenue by job_location doesn't match finance's numbers.

Breaks without it: lineage becomes opaque, bugs hide in intermediate tables, stakeholders lose trust in data, and rework multiplies because you're fixing data quality *after* people have made decisions on it.

## Practice

**Problem:** Your `job_postings_fact` table should only include jobs posted in the last 3 years with a non-null salary, job_title, and location. Duplicate job_ids must not exist. You need to validate these constraints run after the model is built.

```sql
-- models/job_postings_fact.sql
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM {{ ref('stg_job_postings') }}
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '3 years'
  AND salary_year_avg IS NOT NULL
  AND job_title_short IS NOT NULL
  AND job_location IS NOT NULL;

-- tests/job_postings_fact.yml
models:
  - name: job_postings_fact
    columns:
      - name: job_id
        tests:
          - unique
          - not_null
      - name: salary_year_avg
        tests:
          - not_null
          - accepted_values:
              values: [0]  # custom: reject zero salaries
      - name: job_posted_date
        tests:
          - not_null
          - dbt_utils.expression_is_true:
              expression: "job_posted_date >= CURRENT_DATE - INTERVAL '3 years'"
      - name: job_location
        tests:
          - not_null
```

Run `dbt run` to build, then `dbt test` to validate—if any test fails, the exit code signals your orchestrator to halt downstream jobs.

## Notes

- **dbt run + test together** is your contract: the model builds only if tests pass; separating them defeats the purpose.
- **Generic vs. custom tests**: use `unique`, `not_null`, `accepted_values` for standard checks; write custom SQL tests in `tests/` directory for business logic (e.g., salary within realistic ranges).
- **Test coverage cadence**: add tests as bugs surface in production, not after; retroactive testing is debugging dressed up as quality.
- **Orchestration integration**: couple dbt test failures to alerting (Slack, PagerDuty, dbt Cloud) so humans know immediately; silent failures cascade downstream.
- **Connects to**: schema validation, data contracts, CI/CD pipelines, observability (Great Expectations, Monte Carlo), and reconciliation patterns.
