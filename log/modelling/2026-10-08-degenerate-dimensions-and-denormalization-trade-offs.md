---
date: 2026-10-08
phase: modelling
topic: Degenerate dimensions and denormalization trade-offs
---

# Degenerate dimensions and denormalization trade-offs

*Data modelling and warehousing*

## Concept

A **degenerate dimension** is a column in a fact table that looks like a dimension but contains atomic, low-cardinality descriptive data that doesn't warrant its own dimension table. Examples include job title short-form, work-from-home status, or posted date. Including these directly in the fact table avoids unnecessary joins while keeping the schema readable and performant.

The trade-off is between **normalization** (separate dimension tables, reusable, controlled updates) and **denormalization** (fewer joins, simpler queries, faster execution). Degenerate dimensions tip this balance toward denormalization when: the attribute is stable (rarely changes), low-cardinality (few distinct values), and frequently filtered or grouped by analysts. Without this pragmatism, a team wastes query complexity and compute joining to a 50-row dimension just to filter by three job titles.

The risk emerges when degenerate dimensions become inconsistent (misspelled values, inconsistent casing) or when they actually have high cardinality in disguise (job_title_short contains 10,000 variants). Then they degrade into a documentation nightmare—analysts second-guess what "data_engineer_jr" means versus "jr_data_engineer," and you've built a schema that feels simple but behaves like chaos.

## Practice

**Problem:** Your analytics team frequently filters jobs by `job_work_from_home` and `job_location`, but location has 200+ distinct values and changes monthly as new hubs open. The current schema buries these in the fact table with no governance, leading to queries like `WHERE job_location LIKE '%New%'` and inconsistent results.

```sql
-- BEFORE: Degenerate dimensions in fact, no reusability
-- Problem: No way to manage location aliases, team rewrites location logic in every query

-- AFTER: Extract location to a dimension, keep low-cardinality work_from_home in fact
CREATE TABLE locations_dim (
  location_id INT PRIMARY KEY,
  location_name VARCHAR(100),
  city VARCHAR(50),
  country VARCHAR(50),
  region VARCHAR(50),
  updated_at TIMESTAMP
);

CREATE TABLE job_postings_fact (
  job_id INT,
  location_id INT NOT NULL,
  job_title_short VARCHAR(50),  -- Degenerate: low-cardinality, stable
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,   -- Degenerate: 3 distinct values, never changes
  job_posted_date DATE,
  FOREIGN KEY (location_id) REFERENCES locations_dim(location_id)
);

-- Now queries are consistent and location logic lives in one place
SELECT 
  jf.job_title_short,
  COUNT(*) as count_jobs
FROM job_postings_fact jf
INNER JOIN locations_dim ld ON jf.location_id = ld.location_id
WHERE ld.region = 'North America'
  AND jf.job_work_from_home = TRUE
GROUP BY jf.job_title_short;
```

## Notes

- **Cardinality is the key test:** If an attribute has >100 distinct values or grows unbounded, build a dimension. Below 20 and stable? Degenerate is fine.
- **Denormalization couples your fact to business logic:** When you hardcode `job_title_short` in the fact table, renaming titles or adding hierarchies (junior → mid → senior) requires ETL rework, not a dimension table update.
- **Dates are a frequent false degenerate:** Even if `job_posted_date` feels atomic, a date dimension unlocks fiscal calendars, holidays, quarter logic, and time-series joins without query bloat.
- **Document the decision:** Add a comment in your DDL explaining why something stayed denormalized—future you (and your team) won't reverse-engineer intent from schema alone.
- **Connects to: Slowly Changing Dimensions (SCD) and Type 2 tracking.** If an attribute ever changes historically, it should not be degenerate; version it in a dimension instead.
