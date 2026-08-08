---
date: 2026-08-08
phase: sql
topic: Diagnosing a slow join on a large fact table
---

# Diagnosing a slow join on a large fact table

*SQL for analytics and engineering*

## Concept

A slow join on a large fact table typically stems from missing or inefficient indexes, joining on unindexed columns, or scanning the entire table when a filtered subset would suffice. Fact tables are often the largest tables in a warehouse—containing millions or billions of rows—so even a 10% inefficiency multiplies into seconds or minutes of wasted query time. The query planner must decide whether to use a hash join, nested loop, or merge join; without proper indexes on join keys, it defaults to expensive full table scans or sorts.

Diagnosing requires reading the EXPLAIN plan to identify sequential scans where index scans should occur, checking for high actual vs. planned row counts (indicating poor cardinality estimates), and verifying that join predicates filter early. Without addressing slow joins, analytics queries timeout, reports miss SLAs, and downstream data pipelines back up. In interview contexts, you must articulate *why* a join is slow, propose a fix, and estimate the performance impact.

## Practice

**Problem:** You have 15M rows in `job_postings_fact`. A dashboard query filters for data science roles posted in the last 30 days, then joins to a `skills_mapping` table (500K rows) on `job_id`. The query takes 45 seconds. The join is on an unindexed column and no filter is pushed down before the join.

```sql
-- SLOW VERSION (don't do this)
SELECT j.job_id, j.job_title_short, s.skill_name
FROM job_postings_fact j
JOIN skills_mapping s ON j.job_id = s.job_id
WHERE j.job_title_short LIKE '%Data Scientist%'
  AND j.job_posted_date >= CURRENT_DATE - INTERVAL '30 days';

-- FAST VERSION (apply filter first, add indexes)
CREATE INDEX idx_job_postings_title_date 
  ON job_postings_fact(job_title_short, job_posted_date);

CREATE INDEX idx_skills_job_id 
  ON skills_mapping(job_id);

SELECT j.job_id, j.job_title_short, s.skill_name
FROM job_postings_fact j
JOIN skills_mapping s ON j.job_id = s.job_id
WHERE j.job_title_short LIKE '%Data Scientist%'
  AND j.job_posted_date >= CURRENT_DATE - INTERVAL '30 days';
```

The filtered index on `job_postings_fact` reduces the join input from 15M to ~50K rows; the index on `skills_mapping.job_id` enables efficient lookups. Result: 45s → <500ms.

## Notes

- **Index selectivity matters:** An index on a low-cardinality column (e.g., `job_work_from_home`) won't help; prioritize join keys and filter columns with high selectivity.
- **Push filters down:** Always filter `fact` tables before joining. A WHERE clause on the fact table *before* the JOIN is vastly cheaper than filtering after.
- **Read EXPLAIN carefully:** Look for `Seq Scan` vs. `Index Scan`, row count estimates vs. actual rows, and sort operations that indicate missing indexes.
- **Column order in composite indexes:** If filtering by `job_title_short` *and* `job_posted_date`, order the index to match your WHERE clause structure for best performance.
- **Adjacent topics:** Query plan optimization, join strategies (hash vs. nested loop), statistics and cardinality estimates, partitioning large fact tables, and materialized views for repeated slow joins.
