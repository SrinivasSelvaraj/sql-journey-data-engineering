---
date: 2026-10-09
phase: modelling
topic: Ragged hierarchies: variable organizational depth
---

# Ragged hierarchies: variable organizational depth

*Data modelling and warehousing*

## Concept

A ragged hierarchy is an organizational structure where different branches have different depths—some paths are shallow, others deep. In data warehousing, this creates a modelling problem: you can't force a fixed number of columns (e.g., `level_1`, `level_2`, `level_3`) because some entities skip levels or stop early. Without handling this, you either waste columns with NULLs, lose hierarchical relationships, or make queries unnecessarily complex.

Common examples: company org charts (some divisions have 2 levels, others 6), product taxonomies (some products are 2 categories deep, others 4), and geographic boundaries (countries with regions and counties; states with no counties). The issue surfaces when you try to aggregate "give me all jobs by reporting manager" but managers sit at different depths in the tree, so your GROUP BY logic breaks or your JOINs become convoluted.

Without explicit ragged hierarchy design, analysts either hardcode depth assumptions (wrong), construct fragile string parsing logic, or ask you constantly for clarification on what "level 3" means in different contexts.

## Practice

**Problem:** You're asked to report salary by organizational level (e.g., individual contributor, manager, director, VP) but job titles vary wildly, and not every job path has the same reporting depth. Hardcoding `job_level_1`, `job_level_2`, etc. fails because some roles jump from IC to VP.

**Solution:** Create a bridge table that maps each job_id to its logical hierarchy level, allowing variable depth without fixed columns:

```sql
-- Bridge table: job_id → hierarchy path
CREATE TABLE job_hierarchy_bridge (
    job_id INT,
    hierarchy_level INT,
    hierarchy_label VARCHAR(50),  -- 'IC', 'Manager', 'Director', 'VP'
    parent_job_id INT,  -- self-reference for traversal
    hierarchy_path VARCHAR(500)  -- denormalized path for query speed
);

-- Query: average salary by level, regardless of depth
SELECT 
    jh.hierarchy_label,
    COUNT(jf.job_id) as job_count,
    ROUND(AVG(jf.salary_year_avg), 2) as avg_salary
FROM job_postings_fact jf
INNER JOIN job_hierarchy_bridge jh ON jf.job_id = jh.job_id
GROUP BY jh.hierarchy_label
ORDER BY jh.hierarchy_level;
```

This avoids sparse columns and makes the depth implicit in the data, not the schema.

## Notes

- **Bridge tables (type II slowly changing dimensions):** Ragged hierarchies often need bridge tables because the hierarchy itself is a dimension that can shift; track effective dates if organizational structures change.
- **Recursive CTEs are your friend:** Use `WITH RECURSIVE` to traverse variable-depth trees for parent-child queries; avoids hardcoded joins.
- **Denormalization trade-off:** Storing `hierarchy_path` as a string (e.g., "Company > Engineering > Backend") speeds up prefix searches but adds maintenance burden; balance speed vs. maintainability per use case.
- **Adjacency vs. nested sets:** Adjacency lists (parent_id) are flexible for ragged structures but slow for deep subtree queries; nested sets are faster but harder to maintain as the hierarchy changes.
- **Document depth assumptions in metadata:** If you don't have a bridge table, at minimum add a comment or metadata column explaining which entities can appear at which levels; prevents downstream confusion.
