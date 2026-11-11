---
date: 2026-11-11
phase: modelling
topic: Kimball methodology: dimensional modeling and bus matrix
---

# Kimball methodology: dimensional modeling and bus matrix

*Data modelling and warehousing*

## Concept

Kimball dimensional modeling organizes data into **facts** (measurable events, usually numeric) and **dimensions** (descriptive attributes that provide context). A bus matrix is a planning tool that maps business processes (rows) to shared dimensions (columns), ensuring consistency across fact tables and preventing data silos where the same concept is defined differently in different tables.

This matters because analysts need to slice data the same way across the entire warehouse. Without it, one team might filter by `job_location` while another uses `location_name`, and nobody knows if they're comparing apples to apples. The bus matrix forces you to agree on which dimensions are reusable *before* you build tables, not after chaos has set in.

What breaks without it: ambiguous column meanings, dimension tables that duplicate logic, fact tables that can't be joined cleanly, and analysts writing different calculations for the same metric because they started from incompatible schemas.

## Practice

**Problem:** The `job_postings_fact` table mixes facts with dimensional attributes. `job_title_short` is a description (belongs in a dimension), `job_work_from_home` is a yes/no flag (should be in a dimension for consistency), and `job_location` is denormalized (should reference a location key). This makes it hard to reuse location logic for other fact tables (e.g., `applications_fact`) and leaves `job_location` vulnerable to inconsistent spellings.

**Solution:**

```sql
-- Create reusable dimensions
CREATE TABLE dim_job_title (
  job_title_key INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  job_title_category VARCHAR(50)
);

CREATE TABLE dim_location (
  location_key INT PRIMARY KEY,
  location_name VARCHAR(100),
  city VARCHAR(50),
  country VARCHAR(50)
);

CREATE TABLE dim_work_arrangement (
  work_arrangement_key INT PRIMARY KEY,
  is_remote BOOLEAN,
  arrangement_type VARCHAR(50)
);

-- Refactored fact table with foreign keys
CREATE TABLE job_postings_fact (
  job_key INT PRIMARY KEY,
  job_title_key INT REFERENCES dim_job_title,
  location_key INT REFERENCES dim_location,
  work_arrangement_key INT REFERENCES dim_work_arrangement,
  salary_year_avg DECIMAL(10,2),
  job_posted_date DATE,
  FOREIGN KEY (job_title_key) REFERENCES dim_job_title,
  FOREIGN KEY (location_key) REFERENCES dim_location,
  FOREIGN KEY (work_arrangement_key) REFERENCES dim_work_arrangement
);

-- Now locations are consistent across any fact table
SELECT d_loc.city, COUNT(*) as postings
FROM job_postings_fact f
JOIN dim_location d_loc ON f.location_key = d_loc.location_key
GROUP BY d_loc.city;
```

## Notes

- **Denormalization trap:** Kimball *intentionally* denormalizes dimensions into fact tables (via keys) for query speed, but don't denormalize dimension *attributes* into facts—that creates duplicate logic and update nightmares.
- **Bus matrix first:** Sketch the matrix before designing tables. List all business processes (rows) and candidate dimensions (columns), mark which dimensions apply to which processes. This prevents building dimensions nobody uses.
- **Conformed dimensions:** Dimensions shared across multiple fact tables (e.g., `dim_location` used by both `job_postings_fact` and `applications_fact`) must have *identical structure and values* or analysis breaks. This is the hardest part in practice.
- **Slowly Changing Dimensions (SCD):** Real-world dimensions change (job titles evolve, locations rename). Type 1 (overwrite), Type 2 (add timestamp/version rows), or Type 3 (add old/new columns) strategies depend on whether you need historical accuracy.
- **Revisit:** Star schema vs. snowflake schema trade-offs; fact table granularity (one row per job posting vs. one row per job posting *per skill*); handling large dimensions with bridge tables.
