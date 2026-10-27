---
date: 2026-10-27
phase: modelling
topic: Account hierarchies and ownership chains
---

# Account hierarchies and ownership chains

*Data modelling and warehousing*

## Concept

Account hierarchies define parent-child relationships between entities (customers, subsidiaries, departments) and ownership chains track how control or responsibility flows through those relationships. In a data warehouse, this matters because business questions rarely stop at individual accounts—you need to aggregate revenue by parent company, analyze permissions cascading down a department tree, or reconcile consolidated vs. segment reporting. Without explicit hierarchy modeling, you'll either duplicate logic across every query or create "golden source" views that become bottlenecks.

The core challenge is that hierarchies are recursive and can be deep (3 levels or 300). A flat denormalization approach (parent_id, grandparent_id columns) breaks when org structure changes or you need arbitrary-depth traversal. This is where bridge tables or closure tables earn their place: they make hierarchical queries fast and self-documenting, so analysts can write `JOIN account_closure` without needing to ask you how to walk the tree.

## Practice

**Problem:** You need to report total salary spend by company size. Job postings belong to companies, companies belong to parent companies, and some parent companies have their own parents. A posting at a subsidiary should count toward the subsidiary *and* its ultimate parent for consolidated reporting. Show how to structure the schema and query total salary by ultimate parent company.

```sql
-- Hierarchy tables
CREATE TABLE company_account (
  company_id INT PRIMARY KEY,
  company_name VARCHAR(255),
  parent_company_id INT,
  account_level VARCHAR(50)
);

CREATE TABLE company_closure (
  ancestor_id INT,
  descendant_id INT,
  depth INT,
  PRIMARY KEY (ancestor_id, descendant_id)
);

-- Enhanced fact table with company reference
ALTER TABLE job_postings_fact 
ADD COLUMN company_id INT REFERENCES company_account(company_id);

-- Query: total salary by ultimate parent
SELECT 
  ca.company_name AS ultimate_parent,
  SUM(jpf.salary_year_avg) AS total_salary_spend,
  COUNT(jpf.job_id) AS job_count
FROM job_postings_fact jpf
JOIN company_closure cc 
  ON jpf.company_id = cc.descendant_id AND cc.depth = 0
JOIN company_account ca 
  ON cc.ancestor_id = ca.company_id
WHERE cc.depth = (
  SELECT MAX(depth) 
  FROM company_closure 
  WHERE descendant_id = jpf.company_id
)
GROUP BY ca.company_id, ca.company_name
ORDER BY total_salary_spend DESC;
```

## Notes

- **Closure table vs. recursive CTE:** Closure tables are materialized and faster for repeated queries; recursive CTEs are more flexible but slower. Use closure tables in warehouses where the hierarchy is stable and read-heavy.
- **Change capture:** Hierarchies change (reorganizations, acquisitions). Version your closure table with effective_date columns or rebuild it nightly; document the SLA so analysts know if they're seeing real-time or T+1 structure.
- **Depth and path columns matter:** Adding depth to closure tables (as shown) lets you filter to immediate parent, ultimate parent, or any level without extra logic.
- **Adjacent topics:** Slowly Changing Dimensions (SCD Type II) for tracking ownership over time; bridge tables as an alternative for many-to-many relationships; graph databases if your hierarchy is highly dynamic or you need complex traversal patterns.
- **Common mistake:** Storing only parent_id and computing the full closure in every query; this scales poorly and will make your analysts and data platform angry. Pre-compute and materialize.
