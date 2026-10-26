---
date: 2026-10-26
phase: modelling
topic: Hierarchical dimensions and materialized paths
---

# Hierarchical dimensions and materialized paths

*Data modelling and warehousing*

## Concept

A hierarchical dimension is a table that organizes entities into parent–child relationships—think geography (country → state → city), organizational structure (company → department → team), or product catalogs (category → subcategory → SKU). A **materialized path** is a denormalization technique that stores the full ancestry of each node as a string or array in a single column, avoiding expensive recursive joins every time you want to filter or aggregate by level.

Without materialized paths, you either flatten everything into a wide fact table (brittle and denormalized) or normalize it fully and force queries to self-join the dimension table repeatedly. Materialized paths strike the middle ground: one query, no recursion, and you can still slice by any ancestor level using string functions.

This matters when your stakeholders ask questions like "sales by region" or "headcount by department," and you don't want to maintain separate denormalized tables for each level.

## Practice

**Problem:** You need to support queries on job postings grouped by job location at multiple levels: country, state, and city. Queries must run fast without recursive logic, and non-technical users should understand which level they're filtering.

```sql
-- Location dimension with materialized path
CREATE TABLE location_dim (
    location_id INT PRIMARY KEY,
    location_name VARCHAR(100),
    location_type VARCHAR(20),  -- 'country', 'state', 'city'
    parent_location_id INT,
    materialized_path VARCHAR(500)  -- e.g., 'USA/California/San Francisco'
);

-- Fact table references location_id
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR(100),
    salary_year_avg INT,
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    location_id INT REFERENCES location_dim(location_id)
);

-- Query: average salary by state, no recursion needed
SELECT 
    SUBSTRING_INDEX(ld.materialized_path, '/', -2) AS state_path,
    ROUND(AVG(jpf.salary_year_avg), 0) AS avg_salary,
    COUNT(*) AS job_count
FROM job_postings_fact jpf
JOIN location_dim ld ON jpf.location_id = ld.location_id
WHERE ld.materialized_path LIKE 'USA/%'  -- Filter by country
GROUP BY SUBSTRING_INDEX(ld.materialized_path, '/', -2)
ORDER BY avg_salary DESC;
```

## Notes

- **Materialized paths are immutable in practice**: if a location moves in the hierarchy, you either create a new record or accept stale paths. Plan for slowly-changing dimensions (SCD Type 2).
- **String parsing is database-specific**: MySQL uses `SUBSTRING_INDEX`, PostgreSQL uses string arrays, Snowflake uses `SPLIT_PART`. Choose based on your stack and always document the format.
- **Adjacent topics**: slowly-changing dimensions (SCD), bridge tables (for many-to-many hierarchies), and closure tables (an alternative that explicitly stores all ancestor pairs).
- **Common mistake**: storing paths with inconsistent delimiters or varying depths, making parsing fragile. Enforce format strictly in ETL.
- **Revisit when**: your hierarchy becomes truly many-to-many (an employee reports to multiple managers) or needs temporal validity; materialized paths break down—switch to bridge tables or graph approaches.
