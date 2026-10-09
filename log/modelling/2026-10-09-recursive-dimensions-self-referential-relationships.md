---
date: 2026-10-09
phase: modelling
topic: Recursive dimensions: self-referential relationships
---

# Recursive dimensions: self-referential relationships

*Data modelling and warehousing*

## Concept

A recursive dimension is a table that references itself through a foreign key, creating a hierarchy within a single entity. Common examples are organizational charts (employees reporting to managers), product categories (subcategories within categories), or geographic regions (states within countries). Without a recursive dimension, you either flatten the hierarchy (losing structure), create separate tables for each level (inflexible), or ask business users to explain the relationships every time.

The key challenge is that the same table serves dual roles: it holds the entity (e.g., an employee) and points to a parent entity of the same type. This self-reference must be explicit in your schema so analysts can traverse the hierarchy in queries without manual lookups. It matters most when your fact table needs to drill up or down a chain—for example, reporting sales by product category at any depth, or headcount by manager level.

Without recursive dimensions clearly modeled, teams either denormalize (creating brittle wide tables), hardcode hierarchy levels in code, or repeatedly ask you for translation logic. A clean recursive schema makes recursive queries—and the hierarchy itself—discoverable.

## Practice

**Problem:** You need to report total job postings by location at multiple levels (country, state, city). Currently, `job_location` is a flat string. You want analysts to independently group postings by any geographic level without recreating location hierarchies in every query.

```sql
CREATE TABLE location_dim (
  location_id INT PRIMARY KEY,
  location_name VARCHAR(255) NOT NULL,
  location_level VARCHAR(50) NOT NULL, -- 'country', 'state', 'city'
  parent_location_id INT REFERENCES location_dim(location_id),
  CONSTRAINT fk_parent CHECK (parent_location_id != location_id)
);

-- Populate example hierarchy
INSERT INTO location_dim VALUES
(1, 'United States', 'country', NULL),
(2, 'California', 'state', 1),
(3, 'San Francisco', 'city', 2),
(4, 'New York', 'state', 1);

-- Alter fact table to reference dimension
ALTER TABLE job_postings_fact
  ADD COLUMN location_id INT,
  ADD CONSTRAINT fk_location FOREIGN KEY (location_id) REFERENCES location_dim(location_id);

-- Query: postings by state
SELECT l.location_name, COUNT(*) as posting_count
FROM job_postings_fact jpf
JOIN location_dim l ON jpf.location_id = l.location_id
WHERE l.location_level = 'state'
GROUP BY l.location_name;

-- Query: postings by city, with parent state
SELECT l.location_name as city, 
       p.location_name as state,
       COUNT(*) as posting_count
FROM job_postings_fact jpf
JOIN location_dim l ON jpf.location_id = l.location_id
JOIN location_dim p ON l.parent_location_id = p.location_id
WHERE l.location_level = 'city'
GROUP BY l.location_name, p.location_name;
```

## Notes

- **NULL parent trap:** Use explicit NULL for root nodes (no orphan checks), but always document the convention so teams know what "no parent" means.
- **Avoid circular references:** Add a constraint or audit trigger to prevent `A → B → C → A` cycles; recursive CTEs can infinite-loop.
- **Adjacent: bridge tables & slowly changing dimensions.** Recursive dimensions often need Type 2 SCD (effective dates) if hierarchies change—product categories get renamed, org structures reorganize. Track `valid_from` and `valid_to`.
- **Recursive CTEs are your friend.** Use `WITH RECURSIVE` to traverse hierarchies in one query; easier to maintain than application-side tree walks.
- **Performance concern:** Deep hierarchies + large fact tables can slow joins. Index `parent_location_id` and consider materialized lineage tables (store full path as string) for very deep trees.
