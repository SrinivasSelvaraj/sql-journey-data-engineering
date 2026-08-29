---
date: 2026-08-29
phase: modelling
topic: Degenerate dimensions: embedding keys without dimension table
---

# Degenerate dimensions: embedding keys without dimension table

*Data modelling and warehousing*

## Concept

A degenerate dimension is a dimension attribute stored directly in a fact table instead of being normalized into a separate dimension table. It's a key without its own lookup table—the dimension exists only as a column in the fact. Common examples include transaction IDs, order numbers, short codes, or flags that have no meaningful hierarchy or attributes worth storing separately.

Use degenerate dimensions when the attribute is either low-cardinality and stable (like a boolean work-from-home flag), has no related descriptive columns (job title doesn't need a separate lookup), or when normalization creates excessive joins that slow queries without gaining analytical flexibility. Without them, you either over-normalize (creating tiny tables nobody needs) or lose semantic clarity by mixing business keys with metrics.

The risk: if you embed too many attributes directly, your fact table becomes a dumping ground and loses its analytical focus. It's a balance—keep it for truly dimensional attributes that don't warrant their own table, but extract anything with dependencies or future growth potential.

## Practice

**Problem:** You're asked to build a star schema for job postings analytics. The schema above has `job_title_short` embedded directly. Later, you need to analyze salary by job category and job level, but titles are scattered across the fact table with no consistency. You can't aggregate meaningfully, and business users ask "what counts as 'Senior' vs 'Junior'?"

**Solution:** Extract job title into a proper dimension and link it via surrogate key:

```sql
CREATE TABLE job_title_dim (
  job_title_sk INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  job_category VARCHAR(50),
  job_level VARCHAR(20),
  dbt_loaded_at TIMESTAMP
);

CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_sk INT FOREIGN KEY REFERENCES job_title_dim,
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100),
  dbt_loaded_at TIMESTAMP
);

-- Query: salary by level becomes clear
SELECT 
  jt.job_level,
  AVG(jpf.salary_year_avg) as avg_salary
FROM job_postings_fact jpf
JOIN job_title_dim jt ON jpf.job_title_sk = jt.job_title_sk
GROUP BY jt.job_level;
```

The degenerate dimension here is `job_work_from_home`—it stays embedded because it's boolean, stable, and needs no further breakdown.

## Notes

- **Over-embedding hides intent:** A fact table bloated with string columns looks like a raw table, not a curated warehouse. Reviewers won't know what's a key, a degenerate dimension, or a mistake.
- **Cardinality is your guide:** If an attribute has 5–10 unique values and is stable, it's a candidate for degeneracy. If it has 100+ values or grows monthly, normalize it.
- **Connects to:** slowly changing dimensions (SCD), conformed dimensions (sharing dimension tables across fact tables), and grain definition—degenerate dimensions blur grain at your own risk.
- **Common mistake:** Embedding dates as strings or timestamps in the fact table when you should use a date dimension key for easier filtering and aggregation.
- **Revisit when:** adding attributes to an embedded dimension (red flag—extract it now), or when the same "dimension" appears in multiple fact tables (standardize it into a conformed dimension).
