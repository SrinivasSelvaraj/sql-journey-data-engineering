---
date: 2026-08-12
phase: pipelines
topic: dbt: tests, generic and singular
---

# dbt: tests, generic and singular

*Pipelines and orchestration*

## Concept

dbt tests are automated checks that validate data quality and pipeline integrity. **Generic tests** are reusable, parameterized tests (built-in: `unique`, `not_null`, `accepted_values`, `relationships`; or custom) that you configure in YAML. **Singular tests** are one-off SQL queries in `.sql` files that return rows representing failures—if the query returns zero rows, the test passes.

Tests matter because they catch silent data corruption before it propagates downstream. Without them, a job posting with `NULL salary_year_avg` or a duplicate `job_id` silently breaks analytics. Tests also serve as executable documentation—they codify your assumptions about what "correct" data looks like.

When tests fail, dbt stops the pipeline by default (via `--select state:error` or fail-fast behavior in orchestration). This prevents bad data from reaching stakeholders, and forces you to investigate before proceeding. This is "failing loudly"—better to catch a broken model at 6am in CI than have analysts discover bad data in their 2pm dashboard.

## Practice

**Problem:** The `job_postings_fact` table must have a unique, non-null `job_id` for every row, `salary_year_avg` must be positive when present, and `job_posted_date` cannot be in the future.

```sql
-- models/job_postings_fact.yml
models:
  - name: job_postings_fact
    columns:
      - name: job_id
        tests:
          - unique
          - not_null
      - name: salary_year_avg
        tests:
          - accepted_values:
              values: [null]  # or add custom test
      - name: job_posted_date
        tests:
          - dbt_expectations.expect_column_values_to_be_of_type:
              column_type: date

-- tests/singular/job_postings_salary_positive.sql
SELECT *
FROM {{ ref('job_postings_fact') }}
WHERE salary_year_avg IS NOT NULL
  AND salary_year_avg <= 0;

-- tests/singular/job_postings_date_not_future.sql
SELECT *
FROM {{ ref('job_postings_fact') }}
WHERE job_posted_date > CURRENT_DATE;
```

Run tests with `dbt test` or `dbt test --select job_postings_fact`.

## Notes

- **Generic test scope:** Generic tests run *per column* or *per model*; they're best for standard checks. Use them first—they're easier to read and maintain in YAML.
- **Singular test power:** Singular tests let you write complex, multi-column logic (e.g., "salary must be higher than market median for this role in this location"). Use them when generic tests aren't expressive enough.
- **Test selection in CI:** Wire `dbt test` into your pipeline *after* `dbt run`. Use `--select state:modified+` to test only changed models, keeping CI fast; use `--select state:error` to retest failures without rerunning the entire DAG.
- **False negatives:** A test that passes doesn't mean data is *correct*, only that it meets stated constraints. Pair tests with data profiling and manual spot-checks on high-risk columns (e.g., revenue, user IDs).
- **Adjacent topics:** Tests tie into freshness checks (how old is the data?), model contracts (schema versioning), and staging best practices (test early, test raw sources before transformation).
