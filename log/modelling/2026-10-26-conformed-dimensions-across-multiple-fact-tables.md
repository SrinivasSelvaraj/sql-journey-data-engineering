---
date: 2026-10-26
phase: modelling
topic: Conformed dimensions across multiple fact tables
---

# Conformed dimensions across multiple fact tables

*Data modelling and warehousing*

## Concept

A conformed dimension is a dimension table with consistent definitions, grain, and keys that is shared across multiple fact tables. Instead of each fact table maintaining its own copy of dimension attributes (like employee, date, or location), they all reference the same dimension table. This eliminates semantic conflicts: when two teams query salary by location, they're using the same location hierarchy, not divergent definitions.

Without conformed dimensions, you face the "many versions of the truth" problem. One fact table might define "remote work" as work_from_home = TRUE, while another uses a location code of 'REMOTE'. Joins across fact tables become unreliable, and simple questions like "What's our average salary by location?" require reconciliation logic. Users also waste time guessing which column means what.

Conformed dimensions matter most when you have multiple fact tables at different grains (e.g., job_postings_fact and job_applications_fact) that need to slice by the same business entities. A single dimension_location table becomes the contract that guarantees consistency across your warehouse.

## Practice

**Problem:** You have both `job_postings_fact` and `job_applications_fact`. Users want to compare average salary by location across postings *and* applications. Currently, job_postings_fact stores location as raw strings like "New York, NY" or "Remote", making aggregation and joins messy.

**Solution:** Create a conformed dimension_location and foreign-key both fact tables to it.

```sql
-- Create conformed dimension
CREATE TABLE dimension_location (
  location_key INT PRIMARY KEY,
  location_name VARCHAR(100),
  city VARCHAR(50),
  state VARCHAR(2),
  country VARCHAR(50),
  is_remote BOOLEAN
);

-- Populate it (one canonical source of truth)
INSERT INTO dimension_location VALUES
  (1, 'New York, NY', 'New York', 'NY', 'USA', FALSE),
  (2, 'San Francisco, CA', 'San Francisco', 'CA', 'USA', FALSE),
  (3, 'Remote', NULL, NULL, 'USA', TRUE);

-- Refactor fact tables to use location_key
ALTER TABLE job_postings_fact 
  ADD COLUMN location_key INT,
  ADD FOREIGN KEY (location_key) REFERENCES dimension_location(location_key);

-- Now a clean query works across both fact tables
SELECT 
  dl.location_name,
  AVG(jpf.salary_year_avg) AS avg_posting_salary,
  COUNT(DISTINCT jaf.application_id) AS application_count
FROM job_postings_fact jpf
JOIN job_applications_fact jaf ON jpf.job_id = jaf.job_id
JOIN dimension_location dl ON jpf.location_key = dl.location_key
GROUP BY dl.location_name
ORDER BY avg_posting_salary DESC;
```

## Notes

- **Mistake:** Creating a dimension, then letting each fact table slowly diverge its own copy. Version control dimensions like code—store them in a single place, use git/DDL to track changes, and document grain (e.g., "one row per unique city-state-country").

- **Mistake:** Confusing grain. If dimension_location is at the city level, you cannot filter by zip code without adding it as an attribute. Define grain upfront and document it.

- **Adjacent topic:** Slowly Changing Dimensions (SCD) become critical when location attributes change (e.g., a city name changes or a remote policy flips). Plan for Type 1 (overwrite) vs. Type 2 (historical tracking) from the start.

- **Adjacent topic:** Conformed fact tables also matter—ensure both job_postings_fact and job_applications_fact measure similar metrics (e.g., salary) at compatible grains so they can be queried together meaningfully.

- **Worth revisiting:** Role-playing dimensions (e.g., hire_location_key vs. work_location_key both pointing to dimension_location) let you join the same dimension multiple ways on a single fact table—powerful for complex reporting.
