---
date: 2026-11-11
phase: modelling
topic: Dimension hierarchies: levels and level jumping
---

# Dimension hierarchies: levels and level jumping

*Data modelling and warehousing*

## Concept

A dimension hierarchy is an ordered set of levels within a single dimension that represent different grains of aggregation. For example, a date dimension has year → quarter → month → day; a geography dimension has country → region → city → postal code. Level jumping occurs when you aggregate across non-adjacent levels, skipping intermediate ones—such as summing revenue by country and day while ignoring the region and city levels in between.

Dimension hierarchies matter because they enable consistent roll-up and drill-down queries and make aggregations unambiguous. Without explicit hierarchy levels, users query raw columns and either repeat logic across reports or ask you "should I group by job_location or job_title_short?" Every time they ask, you've failed to document the grain and relationships.

Hierarchies break when you mix grains in a single table (a common data warehouse sin). If job_postings_fact conflates job title with seniority level or location with cost center, users cannot reliably aggregate and you lose semantic clarity. The fix is to separate dimensions, establish clear levels, and document which aggregations are valid.

## Practice

**Problem:** Your job_postings_fact table has job_location as a string (e.g. "New York, NY, United States"). You want to aggregate salary spend by country, then by state, then by city—but the free text makes level jumping impossible and reports conflict because normalization varies.

**Solution:** Create a location dimension with explicit levels:

```sql
-- location_dim with clear hierarchical levels
CREATE TABLE location_dim (
    location_id INT PRIMARY KEY,
    country VARCHAR(100) NOT NULL,
    state_province VARCHAR(100),
    city VARCHAR(100),
    postal_code VARCHAR(20)
);

-- Refactored fact table with FK to dimension
ALTER TABLE job_postings_fact 
ADD COLUMN location_id INT,
DROP COLUMN job_location,
ADD CONSTRAINT fk_location FOREIGN KEY (location_id) REFERENCES location_dim(location_id);

-- Now level jumping is explicit and correct
SELECT 
    l.country,
    COUNT(DISTINCT j.job_id) AS job_count,
    AVG(j.salary_year_avg) AS avg_salary
FROM job_postings_fact j
JOIN location_dim l ON j.location_id = l.location_id
GROUP BY l.country;

-- Drill down to state level without recalculating
SELECT 
    l.country, l.state_province,
    COUNT(DISTINCT j.job_id) AS job_count,
    AVG(j.salary_year_avg) AS avg_salary
FROM job_postings_fact j
JOIN location_dim l ON j.location_id = l.location_dim
GROUP BY l.country, l.state_province;
```

## Notes

- **Mistake:** Storing hierarchies as denormalized columns in facts (job_postings_fact with location_country, location_state, location_city). This wastes space and breaks when hierarchies change; use dimensional keys instead.
- **Ragged hierarchies:** Real-world hierarchies are often ragged (some states lack cities, some countries lack regions). Handle with NULLs in intermediate levels and document in data dictionary; never assume a perfect tree.
- **Conformed dimensions:** When the same dimension (e.g., location, date, product) appears in multiple facts, use the same dimension table. This ensures job_postings_fact and employee_dim roll up geography identically.
- **Slowly Changing Dimensions (SCD):** Hierarchies change (cities merge, state boundaries shift). Plan for SCD Type 2 (versioning with effective dates) if history matters; otherwise document when the dimension was last refreshed.
- **Adjacent topic:** Star schema normalization and fact/dimension separation. Hierarchies are why dimensional modelling works; without them, you're just normalizing tables and leaving aggregation logic to users.
