---
date: 2026-10-10
phase: modelling
topic: Centipede fact tables: anti-pattern of over-normalization
---

# Centipede fact tables: anti-pattern of over-normalization

*Data modelling and warehousing*

## Concept

A centipede fact table is a fact table with dozens of foreign keys and minimal measurements—each dimension is normalized to its own table, leaving the fact table as a skeletal join hub. While normalization prevents redundancy, over-normalization in OLAP contexts fractures business logic across too many tables, forcing analysts to write complex joins just to answer simple questions and making the schema self-documenting only to those who know the entire data model.

The pattern matters when your query workload shifts from operational (transaction processing) to analytical (exploratory reporting). A normalized OLTP schema is correct and efficient for updates; a normalized OLAP schema is inefficient and brittle. Analysts need context at their fingertips—job titles, salary ranges, work flexibility—denormalized into a single fact table so a query can be self-contained and readable.

Without denormalization, you lose the ability for junior analysts or business users to query without asking you what `dim_job_category_id = 5` means, or which five tables must join to answer "how many remote mid-level roles pay >$100k?" The centipede pattern pushes knowledge out of the schema and into tribal memory.

## Practice

**Problem:** `job_postings_fact` has a foreign key `job_location` (just an ID), forcing analysts to join `dim_location` to see country, city, timezone. Salary is stored as a numeric year average, requiring recalculation for monthly comparison. Work-from-home is a boolean instead of a categorical label, and `job_posted_date` forces joins to a date dimension for quarter or fiscal period logic. A simple report on "remote roles in EMEA paying $80–120k posted last Q" requires 4+ joins and buries the intent.

**Solution:**

```sql
-- Centipede (anti-pattern): multiple joins required
SELECT COUNT(*)
FROM job_postings_fact jpf
JOIN dim_location dl ON jpf.job_location = dl.location_id
JOIN dim_salary_band dsb ON jpf.salary_year_avg BETWEEN dsb.min_salary AND dsb.max_salary
JOIN dim_work_arrangement dwa ON jpf.job_work_from_home = dwa.arrangement_flag
JOIN dim_date dd ON jpf.job_posted_date = dd.date_key
WHERE dl.region = 'EMEA'
  AND dsb.band_label = 'Mid-range'
  AND dwa.arrangement_label = 'Remote'
  AND dd.fiscal_quarter = 'Q4 2024';

-- Denormalized (better): self-documenting, single table
SELECT COUNT(*)
FROM job_postings_fact_denorm
WHERE location_region = 'EMEA'
  AND salary_band_label = 'Mid-range'
  AND work_arrangement_label = 'Remote'
  AND posted_fiscal_quarter = 'Q4 2024';
```

The denormalized version is readable, maintainable, and requires no schema knowledge beyond column names.

## Notes

- **Centipedes thrive in normalized warehouses**: When a fact table has 20+ foreign keys and fewer than 5 measures, ask if you've normalized for the wrong use case (OLTP thinking in an OLAP context).
- **Dimension denormalization is acceptable**: Flattening a job location into region, country, city, timezone directly in the fact table costs storage but buys query simplicity and self-documentation.
- **Conforms to the "subjectivity test"**: If you must ask colleagues what a column means, it's not a schema—it's a puzzle. Self-service analytics requires denormalization.
- **Related patterns**: Snowflaking (normalizing dimensions further) exacerbates centipede problems; star schema (one level of denormalized dimensions) is the practical antidote.
- **Revisit cardinality and grain**: Before denormalizing, confirm the fact table's grain (one row per job posting) and ensure dimensions don't explode cardinality unnecessarily.
