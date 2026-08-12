---
date: 2026-08-12
phase: pipelines
topic: dbt: macros and DRY SQL
---

# dbt: macros and DRY SQL

*Pipelines and orchestration*

## Concept

Macros in dbt are reusable Jinja2 code blocks that eliminate repetition in SQL transformations. They function like functions in programming—accept parameters, execute logic, and return rendered SQL—allowing you to define business logic once and call it across dozens of models. Without macros, you end up copying identical `CASE` statements, `WHERE` clauses, or data quality checks across your codebase, creating maintenance debt: when a salary tier definition changes, you must hunt down and fix it in 15 different files.

Macros matter most when you have patterns that repeat: standardized transformations (e.g., "convert date strings to timestamps"), domain logic (e.g., "classify job level based on title"), or data quality gates (e.g., "flag null or impossible values"). They're essential for failing loudly because you can centralize validation logic, ensuring consistent errors across the pipeline rather than silent data quality drift in downstream models.

Without macros, DRY (Don't Repeat Yourself) violations accumulate fast. You lose the single source of truth, introduce bugs when updating logic in only some places, and make your dbt project harder to onboard others to. Macros keep your SQL intentional and auditable.

## Practice

**Problem:** You're building salary analysis models and need to consistently categorize jobs into salary bands (entry, mid, senior) across `stg_jobs`, `fct_jobs`, and `mart_compensation` models. The logic is: < $60k = entry, $60k–$100k = mid, $100k+ = senior. Currently you're copying the same `CASE` statement everywhere.

**Solution:**

```sql
{# macros/classify_salary_band.sql #}
{% macro classify_salary_band(salary_column) %}
  CASE 
    WHEN {{ salary_column }} < 60000 THEN 'entry'
    WHEN {{ salary_column }} >= 60000 AND {{ salary_column }} < 100000 THEN 'mid'
    WHEN {{ salary_column }} >= 100000 THEN 'senior'
    ELSE NULL
  END
{% endmacro %}

-- Usage in models/stg_jobs.sql or any model:
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  {{ classify_salary_band('salary_year_avg') }} AS salary_band
FROM {{ source('raw', 'job_postings') }}
WHERE salary_year_avg IS NOT NULL
```

Now if salary thresholds change (e.g., mid-level moves to $65k+), you update once in `macros/classify_salary_band.sql` and all dependent models stay in sync.

## Notes

- **Macro scope:** Macros are project-wide; prefer them for reusable transformations. Use variables for environment-specific configs (prod vs. dev schemas).
- **Testing macros:** Test indirectly through models that use them, or use `dbt test` with custom tests written as macros (`macro_name.sql` in `macros/` with a `macro` block).
- **Common mistake:** Over-parameterizing macros and adding conditional logic inside them. Start simple; if a macro has too many `if` branches, split it into separate macros or reconsider whether it should be a macro at all.
- **Adjacent topics:** Custom tests are macros too; they connect to data quality gates. Variable usage often pairs with macros (e.g., `{{ var('salary_threshold') }}`). Jinja2 loops in macros can generate multiple columns or SQL blocks, reducing boilerplate.
- **Revisit:** Performance—macros render at parse time, not runtime, so they don't slow queries; however, overly complex Jinja2 can slow *dbt parse* if you're generating hundreds of columns. Profile with `dbt parse --debug` if parsing feels slow.
