---
date: 2026-10-27
phase: modelling
topic: Product hierarchies and category trees
---

# Product hierarchies and category trees

*Data modelling and warehousing*

## Concept

Product hierarchies represent the nested, multi-level classification of items in a business—think apparel → mens → shirts → polo shirts. A category tree captures these relationships, allowing aggregation at any level and navigation from specific to general. Without it, you flatten everything into a single "category" column, losing the ability to report on parent categories, enforce consistent naming, or drill down analytically.

This matters most when your business sells thousands of SKUs, operates multiple product lines, or needs to answer questions like "revenue by department" alongside "revenue by brand." Breakdowns occur when analysts query the wrong level of grain, when category names change without history, or when no one can explain why "Electronics" sometimes contains software and sometimes doesn't.

A proper product hierarchy schema separates the tree structure (parent-child relationships in a `dim_product_category` table) from the fact table. Each product record links to a leaf node, and queries traverse the hierarchy to aggregate upward. This is cleaner, more maintainable, and self-documenting than storing "category_level_1, category_level_2, category_level_3" as separate columns.

## Practice

**Problem:** You need to report total salary spend by job location *and* by job work-from-home status, but job_location has 500+ unique values. You want analysts to query meaningful geographic regions (Northeast, Midwest, South, West) without rewriting filters each time.

```sql
-- Create a location dimension with hierarchy
CREATE TABLE dim_job_location (
  location_key INT PRIMARY KEY,
  location_name VARCHAR(100),
  region VARCHAR(50),
  created_at TIMESTAMP
);

-- Foreign-key the fact table
ALTER TABLE job_postings_fact 
ADD COLUMN location_key INT,
ADD FOREIGN KEY (location_key) REFERENCES dim_job_location(location_key);

-- Now analysts can drill cleanly
SELECT 
  d.region,
  jp.job_work_from_home,
  COUNT(*) as job_count,
  AVG(jp.salary_year_avg) as avg_salary
FROM job_postings_fact jp
INNER JOIN dim_job_location d ON jp.location_key = d.location_key
GROUP BY d.region, jp.job_work_from_home
ORDER BY d.region, jp.job_work_from_home;
```

## Notes

- **Denormalization trap:** Resist the urge to store all hierarchy levels in the fact table (location, region, country, continent). Instead, maintain them in the dimension and join at query time—reduces bloat and fixes hierarchy-wide changes in one place.
- **Slowly changing dimensions:** When a product moves categories or a location is renamed, decide upfront whether you track history (SCD Type 2: new row with valid_from/valid_to dates) or overwrite (SCD Type 1). Most warehouses need history for product mix analysis.
- **Recursive CTEs for traversal:** Use `WITH RECURSIVE` to walk hierarchies programmatically—especially useful for "find all descendants of Electronics" queries without manually nesting joins.
- **Grain mismatch:** Ensure every fact record points to a *leaf* node in the hierarchy. Assigning a job posting to "Apparel" rather than "Apparel > Mens > Shirts" will confuse roll-ups and cause double-counting.
- **Adjacent topics:** Connects to star schema design (dimensions vs. facts), conformed dimensions (shared hierarchies across fact tables), and bridge tables (for many-to-many category relationships, e.g., a product in multiple categories).
