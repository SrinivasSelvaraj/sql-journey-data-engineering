---
date: 2026-10-09
phase: modelling
topic: Star schema: normalized vs denormalized trade-offs
---

# Star schema: normalized vs denormalized trade-offs

*Data modelling and warehousing*

## Concept

A star schema balances normalized dimension tables (low redundancy, update safety) against denormalized fact tables (query speed, fewer joins). The normalized path isolates job titles into a `dim_job_title` table; the denormalized path stores `job_title_short` directly in the fact table. This trade-off matters because every join adds latency and cognitive load—queries that touch 8 tables run slower and are harder to reason about—but storing redundant data risks inconsistency when a job title changes and you forget to update it in 47 fact rows.

In practice, you denormalize when the dimension is stable (dates, geographies, fixed categories) or when query speed dominates (OLAP warehouse reads). You normalize when the dimension changes frequently (job titles evolving, salary ranges shifting) or when storage is constrained. Without clarity on this choice, teams end up with slowly-changing dimensions that nobody updates, or dimension tables so joined-together that the star schema becomes a relational schema masquerading as a warehouse.

The real cost is hidden: a denormalized fact table is fast *today* but becomes a maintenance burden and source of truth conflicts *tomorrow*. A fully normalized schema is clean but can collapse under join cardinality.

## Practice

**Problem:** The `job_postings_fact` table stores `job_title_short` directly. Now your marketing team wants to tag job titles as "high-growth" or "legacy." If you update only the fact table, historical records show inconsistent labels. If you create a separate lookup, you've broken denormalization but gained maintainability.

**Solution: Use a Type 2 slowly-changing dimension**

```sql
-- Create normalized dimension with validity window
CREATE TABLE dim_job_title (
  job_title_key INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  is_high_growth BOOLEAN,
  effective_date DATE,
  end_date DATE,
  is_current BOOLEAN
);

-- Fact table now references the key, not the string
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_key INT REFERENCES dim_job_title(job_title_key),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100)
);

-- Query joins on key; dimension controls interpretation
SELECT 
  f.job_id,
  d.job_title_short,
  d.is_high_growth,
  f.salary_year_avg
FROM job_postings_fact f
JOIN dim_job_title d ON f.job_title_key = d.job_title_key
WHERE d.is_current = TRUE
  AND d.is_high_growth = TRUE;
```

## Notes

- **Denormalization creep**: Start with a normalized star; denormalize only when profiling shows joins are the bottleneck, not when "it seems like it might be slow."
- **Slowly-changing dimensions (SCD types)**: Type 1 overwrites (loses history), Type 2 adds rows with validity dates (preserves history, adds complexity), Type 3 adds columns (rare middle ground). Choose upfront.
- **Grain consistency**: All fact rows must represent the same business event (one row per job posting). Mixing grains (some rows per posting, some per posting+location) breaks all downstream aggregations.
- **Document the decision**: Write down *why* a column is denormalized (performance? ease of consumption?). Future you—and your team—will thank you when push-back comes.
- **Adjacent: data vault modeling** uses hubs (entities), links (relationships), and satellites (attributes over time) to handle both denormalization and slowly-changing dimensions more systematically.
