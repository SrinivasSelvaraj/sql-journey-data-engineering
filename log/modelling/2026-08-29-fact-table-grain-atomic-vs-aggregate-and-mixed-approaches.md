---
date: 2026-08-29
phase: modelling
topic: Fact table grain: atomic vs aggregate and mixed approaches
---

# Fact table grain: atomic vs aggregate and mixed approaches

*Data modelling and warehousing*

## Concept

A fact table's **grain** defines the finest level of detail (atomicity) at which a row represents a business event or measurement. Atomic grain captures every transaction or event as it occurred—one row per job application, per click, per sale—preserving all dimensions and enabling drill-down queries. Aggregate grain pre-computes summaries (total revenue by region per month, average salary by job level) to optimize query speed at the cost of detail loss.

Mixed-grain approaches store both: atomic facts for detailed analysis and pre-aggregated facts for reporting dashboards. This requires careful namespace separation and explicit documentation so analysts don't accidentally join or double-count. Without grain clarity, queries silently produce wrong results—summing pre-aggregated salary figures alongside atomic job counts, for example, inflates totals without warning.

Choosing grain is a tradeoff: atomic maximizes flexibility and correctness but requires computational power at query time; aggregates minimize query latency but lock you into predefined groupings and break if business questions change shape.

## Practice

**Problem:** Your `job_postings_fact` table mixes atomic and aggregate grain. `job_posted_date` is atomic (one row per posting), but `salary_year_avg` and `job_work_from_home` are already rolled up by job title. When you sum `salary_year_avg` grouped by `job_title_short`, you're summing aggregates—producing inflated figures if multiple postings share the same title.

**Solution:** Split into two tables with explicit grain:

```sql
-- Atomic grain: one row per job posting
CREATE TABLE job_postings_fact_atomic (
  job_posting_id INT PRIMARY KEY,
  job_id INT,
  job_title_short VARCHAR,
  salary_year_min INT,
  salary_year_max INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR
);

-- Aggregate grain: one row per job title per month
CREATE TABLE job_postings_fact_agg_monthly (
  job_title_short VARCHAR,
  job_posted_month DATE,
  posting_count INT,
  avg_salary_year INT,
  pct_work_from_home DECIMAL,
  PRIMARY KEY (job_title_short, job_posted_month)
);

-- Safe query: sum atomic facts
SELECT job_title_short, COUNT(*), AVG(salary_year_max)
FROM job_postings_fact_atomic
GROUP BY job_title_short;

-- Fast query: use pre-aggregated table (no arithmetic needed)
SELECT job_title_short, job_posted_month, avg_salary_year
FROM job_postings_fact_agg_monthly
WHERE job_posted_month >= '2024-01-01';
```

## Notes

- **Grain mismatch is silent:** SQL doesn't warn you when you sum pre-aggregated values; results look plausible but are mathematically wrong. Document grain in table comments and lineage.
- **Additive vs. non-additive measures:** Atomic grain lets you SUM, COUNT, and AVG safely across any dimension. Aggregates with pre-computed percentages or averages are *non-additive*—you cannot re-aggregate them correctly.
- **Bridge tables and conformed dimensions:** Mixed-grain warehouses need explicit foreign keys and conformed dimension tables (e.g., `dim_job_title`) so both atomic and aggregate facts point to the same version of truth.
- **Revisit grain during schema reviews:** As business questions evolve (new drill-down dimensions, unexpected slices), atomic grain rarely needs redesign; aggregates often become obstacles.
- **Related: slowly changing dimensions (SCD), fact-less fact tables, and snapshot tables**—all affect how grain interacts with temporal and dimensional change.
