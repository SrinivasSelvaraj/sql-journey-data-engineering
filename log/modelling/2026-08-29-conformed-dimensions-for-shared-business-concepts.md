---
date: 2026-08-29
phase: modelling
topic: Conformed dimensions for shared business concepts
---

# Conformed dimensions for shared business concepts

*Data modelling and warehousing*

## Concept

A conformed dimension is a reusable, consistent table that represents a shared business concept—like Date, Location, or Job Category—used across multiple fact tables. Instead of each fact table defining its own version of "location" or "job type," they all reference the same dimension, ensuring a single source of truth for that entity's attributes and definitions.

Without conformed dimensions, you end up with semantic inconsistency: one team's fact table has `job_location_name` as free text, another has `location_id` pointing to a proprietary lookup, and a third has coordinates. When someone queries both tables, they can't join them meaningfully, and reporting requires translation layers. The warehouse becomes fragmented into fiefdoms rather than a unified model.

Conformed dimensions matter most when you have multiple fact tables (job postings, applications, hires) that all need to reference the same concepts. They enable self-service analytics: a user can join `job_postings_fact` to `applications_fact` using a shared dimension without calling you to ask "does your location ID match mine?"

## Practice

**Problem:** `job_postings_fact` stores `job_location` as free text (e.g., "New York, NY", "Remote", "New York, New York"). When joined with an `applications_fact` table that uses the same location field, some rows fail to match because of inconsistent formatting. A report counting postings and applications by city produces misleading nulls and duplicates.

**Solution:** Create a conformed location dimension and reference it from both fact tables.

```sql
-- Create the conformed location dimension (once, shared)
CREATE TABLE dim_location (
  location_id INT PRIMARY KEY,
  city VARCHAR(100) NOT NULL,
  state_province VARCHAR(100),
  country VARCHAR(100),
  is_remote BOOLEAN,
  created_at TIMESTAMP
);

INSERT INTO dim_location VALUES
  (1, 'New York', 'NY', 'USA', FALSE, CURRENT_TIMESTAMP),
  (2, 'San Francisco', 'CA', 'USA', FALSE, CURRENT_TIMESTAMP),
  (3, NULL, NULL, NULL, TRUE, CURRENT_TIMESTAMP);  -- Remote

-- Refactor job_postings_fact to reference the dimension
ALTER TABLE job_postings_fact
  ADD COLUMN location_id INT REFERENCES dim_location(location_id),
  DROP COLUMN job_location;

-- Now both fact tables use the same location_id
-- Joins are unambiguous and efficient
SELECT 
  dl.city,
  dl.state_province,
  COUNT(jp.job_id) AS posting_count,
  COUNT(af.application_id) AS application_count
FROM dim_location dl
LEFT JOIN job_postings_fact jp ON dl.location_id = jp.location_id
LEFT JOIN applications_fact af ON dl.location_id = af.location_id
GROUP BY dl.city, dl.state_province;
```

## Notes

- **Slowly changing dimensions (SCD):** Location names or job titles may change over time. Decide whether you need SCD Type 1 (overwrite), Type 2 (version with dates), or Type 3 (previous value column). This affects how you handle historical accuracy.

- **Over-normalization trap:** Not every column needs its own dimension. Conformed dimensions are for concepts shared *across* fact tables. A column used by only one fact table should stay denormalized in that fact table to avoid unnecessary joins.

- **Bridges and many-to-many:** A job posting might span multiple locations; a location might have multiple timezone rules. Use bridge tables (e.g., `job_location_bridge`) if a many-to-many relationship exists, rather than forcing a 1:N design.

- **Governance and naming:** Conformed dimensions require cross-team agreement on definitions. Document what "Remote" means, whether state codes are ISO 3166 or custom, and who owns maintaining the dimension. Naming conventions (e.g., `dim_*` prefix) signal intent.

- **Surrogate vs. natural keys:** Use surrogate keys (auto-increment `location_id`) as foreign keys in fact tables, not natural keys like city name. Natural keys are brittle; surrogates let you change display text without updating millions of rows.
