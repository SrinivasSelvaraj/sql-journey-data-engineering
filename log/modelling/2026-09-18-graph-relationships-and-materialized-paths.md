---
date: 2026-09-18
phase: modelling
topic: Graph relationships and materialized paths
---

# Graph relationships and materialized paths

*Data modelling and warehousing*

## Concept

Graph relationships in data warehouses represent hierarchical or networked connections between entities—like organizational reporting structures, product category trees, or job skill dependencies. A **materialized path** stores the full ancestor chain as a denormalized string or array in each row, enabling fast traversal without recursive queries. For example, instead of joining a self-referential table multiple times to find "all ancestors of Product X," you store the path directly: `/root/electronics/laptops/gaming-laptops`.

This matters when your queries must filter, group, or aggregate across levels without knowing the tree depth in advance. Materializing paths trades storage for query speed and simplicity—critical in analytics where 50+ joins become unacceptable. It breaks down when hierarchies change frequently (paths become stale) or when you need bidirectional traversal (parent→child and child→parent queries equally).

The schema explicitness matters most here: if `job_location` contains nested geography (city, state, country), a materialized path column like `location_path` (`/USA/California/San Francisco`) lets analysts write readable GROUP BY and WHERE clauses without domain knowledge about your location table structure.

## Practice

**Problem:** You need to analyze salary trends across job locations organized hierarchically (country → state → city). Marketing wants to compare "all US salaries" against "all European salaries" in a single query, without knowing your location table structure.

```sql
-- Add materialized path to job_postings_fact during ETL
ALTER TABLE job_postings_fact 
ADD COLUMN location_path VARCHAR(500);

-- Example: '/USA/California/San Francisco', '/USA/Texas/Austin'

-- Query: average salary by region, no joins needed
SELECT
  SPLIT_PART(location_path, '/', 2) AS country,
  SPLIT_PART(location_path, '/', 3) AS state,
  ROUND(AVG(salary_year_avg)) AS avg_salary,
  COUNT(*) AS job_count
FROM job_postings_fact
WHERE location_path LIKE '/USA/%'
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY 1, 2
ORDER BY avg_salary DESC;
```

## Notes

- **Path maintenance during updates:** If a location is renamed or reorganized, all downstream paths must be recalculated. Use triggers or rebuild the column in your transformation layer, never manually.
- **Delimiter choice matters:** Use `/` or `|` consistently; avoid delimiters that might appear in names. Document the format in your schema metadata.
- **Alternative: nested sets and closure tables.** Materialized paths suit read-heavy hierarchies; closure tables (storing all ancestor–descendant pairs) scale better for frequent structural changes.
- **Analytic functions vs. materialized paths:** Window functions like `ROW_NUMBER() OVER (PARTITION BY ...)` can replace paths for ranking within levels, but paths excel at "all descendants" filters without subqueries.
- **Revisit when:** Hierarchies deepen unexpectedly (paths become too long for indexes), or when you need to traverse sideways (sibling comparisons)—then reconsider graph databases or denormalizing into separate dimension tables per level.
