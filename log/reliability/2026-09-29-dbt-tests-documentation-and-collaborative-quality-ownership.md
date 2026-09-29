---
date: 2026-09-29
phase: reliability
topic: dbt tests: documentation and collaborative quality ownership
---

# dbt tests: documentation and collaborative quality ownership

*Quality, reliability and the professional layer*

## Concept

dbt tests serve a dual purpose: they enforce data quality rules and they communicate expectations to your team. A test without documentation is a mystery—it runs silently and fails cryptically. A well-documented test becomes a contract: "this column must never be null," "salary must be positive," "job_posted_date cannot be in the future." This matters because data pipelines don't fail catastrophically; they fail subtly. A NULL sneaks into salary_year_avg and downstream analytics report inflated averages. Without documented tests, you discover this in production. With them, you catch it in CI/CD and, critically, your team understands *why* the rule exists before they try to change it.

The difference between someone who builds pipelines and someone trusted to own them is this: builders write queries; owners write tests and explain them. Ownership means you've made the implicit explicit. You've codified assumptions. When a stakeholder asks "why can't we have NULL salaries?", you point to the test, the model schema, and the documentation explaining the business rule. This shifts quality from your shoulders alone to the entire team—collaborative quality ownership.

Tests fail without documentation in real ways: someone deletes a test they don't understand, a junior analyst bypasses quality checks, a stakeholder demands an exception without context for why the rule existed. You lose institutional knowledge and revert to reactive debugging.

## Practice

**Problem:** Your job_postings_fact table has inconsistent salary data. Some records have NULL salary_year_avg (remote roles, undisclosed). Some have obviously wrong values (999999, negative numbers from data entry errors). You need tests that catch real problems without false alarms, and your team needs to understand the rules.

```sql
-- models/job_postings_fact.yml
version: 2
models:
  - name: job_postings_fact
    description: Fact table of job postings with cleaned and validated attributes.
    columns:
      - name: job_id
        description: Unique identifier for the job posting.
        tests:
          - unique
          - not_null
      
      - name: salary_year_avg
        description: Annual salary in USD. NULL for undisclosed/remote roles without published ranges.
        tests:
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 20000
              max_value: 500000
              config:
                where: "salary_year_avg IS NOT NULL"
          - dbt_expectations.expect_column_values_to_be_null:
              config:
                where: "job_work_from_home = TRUE AND job_location LIKE '%Remote%'"
                description: "Remote roles without location specificity should have NULL salary (no data available)."
        
      - name: job_posted_date
        description: Date the job was posted.
        tests:
          - not_null
          - dbt_utils.recency:
              datepart: day
              interval: 90
              description: "Ensures we're loading recent data; gaps > 90 days signal pipeline failure."

generic_tests:
  - name: salary_believable
    description: |
      Ensures salary values are realistic.
      - Non-null salaries must be between $20k–$500k (adjusted for role level).
      - Negative or zero salaries are data entry errors and must fail.
    sql: |
      SELECT *
      FROM {{ table }}
      WHERE salary_year_avg < 0 OR salary_year_avg = 0
```

## Notes

- **Documentation is not optional:** Tests without context are technical debt. Write *why* the rule exists (business rule? data quality? SLA?) not just what it checks.

- **Ownership means explainability:** When a test fails, your team should know if it's a real problem (bad data) or a rule that needs updating (business changed). Document the action.

- **False alarms destroy trust:** Tests that fail for known, acceptable reasons (NULLs in salary, future-dated jobs in edge cases) need conditional logic and clear explanation. Too many ignored failures breed a culture that ignores *all* failures.

- **Connect to schema contracts:** Test documentation should reference your dbt schema.yml. Together they form the contract: columns, types, nullability, and quality rules in one place. Use `description` and `meta` tags liberally.

- **Revisit: collaborative code review for tests** — tests should be reviewed like code. Does the rule make sense? Is the documentation clear enough for someone joining next month to understand and maintain it?
