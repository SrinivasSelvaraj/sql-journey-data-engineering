---
date: 2026-08-19
phase: sql
topic: Querying nested arrays and structs in BigQuery
---

# Querying nested arrays and structs in BigQuery

*SQL for analytics and engineering*

## Concept

BigQuery supports nested and repeated fields (arrays and structs) natively within columns, enabling you to store and query hierarchical data without flattening. A `STRUCT` is a composite type containing multiple named fields (like a dictionary); an `ARRAY` is an ordered collection, often of structs. Querying them requires special syntax: `UNNEST()` to flatten arrays into rows, dot notation to access struct fields, and `ARRAY_AGG()` to reconstruct them.

This matters because denormalized, nested schemas reduce join complexity, improve query performance for hierarchical data, and align with how modern applications structure JSON. Without mastering `UNNEST()` and struct access, you'll either write inefficient multi-way joins or return incorrect results by forgetting that array fields implicitly cross-join rows.

A common failure: selecting a struct field directly without `UNNEST()` returns all array elements concatenated as a single value, or fails with "Cannot access field X on a value with type ARRAY." Another: forgetting that `UNNEST()` creates a new row per array element, which can cause accidental duplication when joined back to the outer table.

## Practice

**Problem:** Given a table where each `job_postings_fact` row may have multiple `required_skills` (an ARRAY of STRUCTs, each with `skill_name STRING` and `proficiency_level STRING`), write a query that lists every unique skill required across all postings, along with the count of jobs requiring that skill and the average salary for jobs requiring it.

```sql
SELECT
  skill.skill_name,
  COUNT(DISTINCT job_id) AS job_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM job_postings_fact
CROSS JOIN UNNEST(required_skills) AS skill
WHERE salary_year_avg IS NOT NULL
GROUP BY skill.skill_name
ORDER BY job_count DESC;
```

## Notes

- **UNNEST() creates a row-multiplicative join:** if a job has 5 skills, it produces 5 output rows. Always verify your expected cardinality; use `COUNT(DISTINCT job_id)` to avoid over-counting.
- **Struct field access uses dot notation:** `skill.skill_name` works after `UNNEST`, but `required_skills.skill_name` (without unnest) fails or returns nested arrays.
- **Array aggregation reverses unnesting:** use `ARRAY_AGG(STRUCT(field1, field2))` or `ARRAY_AGG(STRUCT(...) ORDER BY ...)` to reconstruct nested data for GROUP BY results.
- **Filtering nested fields:** apply predicates either before `UNNEST` (on the outer table) or after (on the flattened columns); be aware of which rows get eliminated in each case.
- **Adjacent topics:** window functions over unnested data, repeated field schema design, and cost implications of denormalization vs. normalization in columnar storage.
