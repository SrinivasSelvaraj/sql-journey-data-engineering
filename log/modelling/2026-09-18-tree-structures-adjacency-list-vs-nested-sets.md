---
date: 2026-09-18
phase: modelling
topic: Tree structures: adjacency list vs nested sets
---

# Tree structures: adjacency list vs nested sets

*Data modelling and warehousing*

## Concept

Tree structures appear constantly in data warehousing: organizational hierarchies, product taxonomies, geographic regions, account rollups. Two models dominate: **adjacency list** (each node stores its parent's ID) and **nested sets** (each node stores left/right boundaries in a pre-order traversal). Adjacency lists are intuitive and cheap to insert/update; nested sets are expensive to modify but blazingly fast for subtree queries and aggregations.

The choice matters because it determines whether you can answer "show me all jobs in the Northeast region and its subregions" in one join or need recursive CTEs. Without explicit structure, either you denormalize (breaking single-source-of-truth), or teams query your raw data wrong and get partial results they don't realize are incomplete.

In data warehouses, adjacency lists suit slowly-changing dimensions where inserts are rare but reads are constant (org charts). Nested sets suit static taxonomies (job categories, geography) where you pre-compute and never touch them. Picking wrong means either 50-table joins or 15-minute recursive queries on every dashboard refresh.

## Practice

**Problem:** Your job_postings_fact has job_category_id (e.g., "Senior Data Engineer" → "Data" → "Technology" → root), and you need to aggregate salary_year_avg by region *including all subregions*. Location is hierarchical: "Boston" → "New England" → "Northeast" → root. Build a schema and query that sums average salary by top-level region without recursion overhead.

```sql
-- Nested set schema: region_dim with lft/rgt boundaries
CREATE TABLE region_dim (
  region_id INT PRIMARY KEY,
  region_name VARCHAR(100),
  region_level INT,
  lft INT NOT NULL,
  rgt INT NOT NULL
);
-- Example: Northeast (lft=2, rgt=9) contains New England (lft=3, rgt=6)
-- which contains Boston (lft=4, rgt=5)

-- Query: sum salaries for all jobs in Northeast and descendants
SELECT 
  r.region_name,
  COUNT(*) as job_count,
  ROUND(AVG(j.salary_year_avg), 0) as avg_salary
FROM job_postings_fact j
INNER JOIN region_dim r ON j.job_location = r.region_name
INNER JOIN region_dim parent ON r.lft BETWEEN parent.lft AND parent.rgt
WHERE parent.region_name = 'Northeast'
GROUP BY r.region_name
ORDER BY r.lft;
```

This single join replaces a recursive CTE; the lft/rgt predicate captures the entire subtree in one condition.

## Notes

- **Adjacency list trap:** Self-joins for "children of parent" are readable but `WHERE parent_id = @node` repeated down a tree becomes `O(depth)` queries. Recursion costs balloon at scale.
- **Nested set maintenance:** Updating lft/rgt when inserting a middle node requires renumbering siblings downstream. Only use if the tree is append-only or rebuilt nightly from source.
- **Hybrid approach:** Store both in the dimension table (parent_id + lft/rgt) if your warehouse can afford the space; queries run fast and inserts stay simple, at the cost of sync discipline.
- **Related:** Materialized path (e.g., storing "/Northeast/New England/Boston" as a string) is easier than nested sets to maintain but slower to query; consider for low-cardinality dimensions.
- **Testing:** Verify subtree queries return the right row count; nested set boundary mistakes are silent and hard to spot in aggregations.
