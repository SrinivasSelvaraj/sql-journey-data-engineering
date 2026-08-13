---
date: 2026-08-13
phase: cloud
topic: Redshift: distribution keys and sort keys
---

# Redshift: distribution keys and sort keys

*Cloud platforms and storage*

## Concept

A **distribution key** determines which node in a Redshift cluster stores each row, while a **sort key** determines the physical order of rows within each node. Distribution keys control *horizontal* data movement (across nodes), whereas sort keys optimize *vertical* scans (within a node). Choosing poorly forces expensive network shuffles during joins or full table scans when range filters could prune blocks.

Without a thoughtful distribution key, queries that join two large tables will redistribute one or both tables across the network—a massive performance hit. Without a sort key aligned to your filter patterns, Redshift cannot skip blocks during WHERE clauses or aggregations, forcing reads of data you won't use. Both decisions are permanent (or expensive to change), so they must reflect your actual query patterns, not hypothetical ones.

In practice: pick a distribution key that minimizes shuffle during your most frequent joins (often a foreign key), and pick a sort key that matches your most selective filters and GROUP BY operations. Measure skew and query execution plans before committing.

## Practice

**Problem:** Your analytics team frequently filters job postings by `job_posted_date` and `job_location`, and joins job_postings_fact to a company dimension on `job_id`. Queries are slow. Design the table.

```sql
CREATE TABLE job_postings_fact (
    job_id INT,
    job_title_short VARCHAR(50),
    salary_year_avg INT,
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR(100),
    PRIMARY KEY (job_id)
)
DISTKEY (job_id)
SORTKEY (job_posted_date, job_location);
```

**Why:** `job_id` as DISTKEY ensures joins to company dimensions co-locate data on the same node (no shuffle). `job_posted_date` first in SORTKEY enables range pruning for date filters; `job_location` second enables efficient GROUP BY on location. If queries filter heavily on location first, reverse the sort key order.

## Notes

- **Skew trap:** if your DISTKEY has imbalanced cardinality (e.g., one job_id appearing 1M times), data piles onto one node. Use DISTKEY EVEN (round-robin) for fact tables with no obvious join key, accepting the shuffle cost as the lesser evil.
- **Sort key is not an index:** Redshift doesn't use B-trees. Sort keys only help if queries filter or group on those columns *in order*; a filter on column 2 without filtering column 1 gets no benefit (zone maps still apply, but less effectively).
- **Compound keys multiply storage:** adding a third sort key column increases metadata overhead. Stick to 2–3 columns aligned with real query patterns, not wishful thinking.
- **Connects to:** VACUUM and ANALYZE to maintain sort order and statistics; query explain plans (VERBOSE mode) to confirm Redshift actually uses your sort keys; table design review before loading 100GB+.
- **Revisit when:** access patterns shift (new dashboard, new use case) or you see DS_DIST_ALL_NONE in execution plans (that's the shuffle smoking gun).
