---
date: 2026-09-18
phase: modelling
topic: Product hierarchies and category tree navigation
---

# Product hierarchies and category tree navigation

*Data modelling and warehousing*

## Concept

Product hierarchies organize items into nested parent-child relationships—Category → Subcategory → Product Type → SKU—enabling queries at any level of aggregation. Without explicit hierarchy tables, you either flatten everything (losing roll-up capability) or embed parent IDs in fact tables (creating redundancy and update nightmares). A well-designed category tree lets analysts ask "revenue by department" and "revenue by brand within department" from the same schema without reloading data.

Hierarchies matter when business questions span multiple grain levels: retail needs margin by store, district, region, and national; SaaS needs churn by tier, feature cohort, and industry vertical. Breaking this happens when you store category names as strings in fact tables—renaming a category means updating millions of rows, and you lose the ability to compare "old category" vs. "new category" in historical context.

The standard approach uses a slowly-changing dimension (SCD Type 2): a category dimension table with surrogate keys, effective dates, and a parent_category_id self-reference. This separates schema changes (new hierarchy levels or reparenting) from fact data, keeps queries fast, and preserves audit trails.

## Practice

**Problem:** You need to report total salary spend by job location hierarchy (Country → Region → City), but the job_postings_fact table only has a flat job_location string. You also need to handle location renames (e.g., "SF Bay Area" → "San Francisco Bay Area") without breaking historical analysis.

```sql
-- Create location dimension with hierarchy
CREATE TABLE location_dim (
    location_id INT PRIMARY KEY,
    location_name VARCHAR(100),
    parent_location_id INT REFERENCES location_dim(location_id),
    location_level VARCHAR(20), -- 'country', 'region', 'city'
    effective_date DATE,
    end_date DATE,
    is_current BOOLEAN,
    FOREIGN KEY (parent_location_id) REFERENCES location_dim(location_id)
);

-- Denormalized bridge for fast aggregation (optional, trade-off for performance)
CREATE TABLE location_bridge (
    location_id INT,
    city_id INT,
    region_id INT,
    country_id INT,
    PRIMARY KEY (location_id)
);

-- Query: Salary by region with historical consistency
SELECT 
    ld_region.location_name AS region,
    SUM(jpf.salary_year_avg) AS total_salary_spend
FROM job_postings_fact jpf
JOIN location_dim ld_city 
    ON jpf.job_location = ld_city.location_name 
    AND ld_city.is_current = TRUE
JOIN location_dim ld_region 
    ON ld_city.parent_location_id = ld_region.location_id
WHERE jpf.job_posted_date BETWEEN '2024-01-01' AND '2024-12-31'
GROUP BY ld_region.location_name
ORDER BY total_salary_spend DESC;
```

## Notes

- **SCD Type 2 is essential for hierarchies:** Use effective_date/end_date on dimension records, not fact tables. If "Northeast" is renamed to "New England," old fact rows still point to the old dimension record; new posts pick up the new one. Never UPDATE dimension records—always INSERT new versions.

- **Beware circular references:** Self-joins on parent_id are powerful but risky. Add a recursive query or materialized path column (e.g., `hierarchy_path = '/country/region/city'`) to prevent infinite loops and simplify depth queries.

- **Denormalization patterns:** For large hierarchies (1000+ categories), consider a bridge table or closure table that pre-computes all ancestor–descendant pairs. Queries become simpler (`JOIN location_bridge ON location_bridge.location_id = fact.location_id`), but insert/update logic is more complex.

- **Connects to:** Slowly Changing Dimensions (SCD), recursive CTEs, star schema design, fact table grain decisions. Also relevant to handling organizational charts and bill-of-materials schemas.

- **Revisit:** How to handle reparenting events (e.g., a product moves from Category A to Category B). SCD Type 2 handles attribute changes, but moving hierarchies needs careful tracking of which facts belong to which branch at query time.
