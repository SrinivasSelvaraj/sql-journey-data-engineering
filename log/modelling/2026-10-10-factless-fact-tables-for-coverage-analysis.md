---
date: 2026-10-10
phase: modelling
topic: Factless fact tables for coverage analysis
---

# Factless fact tables for coverage analysis

*Data modelling and warehousing*

## Concept

A factless fact table contains only foreign keys and dimensional attributes—no numeric measures—and is used to record events or coverage rather than quantities. It answers "did this happen?" instead of "how much?" In data warehousing, this matters when you need to track relationships between dimensions (e.g., which job titles appear in which locations) or analyze the *existence* of something across time periods without aggregating a metric.

Without factless fact tables, you either create artificial measures (like a count of 1 per row, which inflates during joins) or embed dimensional relationships into dimension tables themselves, breaking normalization and making it hard to slice by multiple dimensions independently. For coverage analysis—"what skills are demanded across regions?" or "which job types are available remote?"—factless tables let you query presence without distorting cardinality.

## Practice

**Problem:** You need to answer "For each job title, how many distinct locations does it appear in?" and separately "For each location, how many distinct job titles are posted?" These are dimension-to-dimension relationships. If you try to answer them from the original table, you'll either double-count or write complex distinct clauses.

**Solution:** Create a factless fact table:

```sql
CREATE TABLE job_posting_coverage_fact (
  job_posting_id INT PRIMARY KEY,
  job_title_key INT NOT NULL,
  job_location_key INT NOT NULL,
  job_posted_date DATE NOT NULL,
  FOREIGN KEY (job_title_key) REFERENCES job_title_dim(job_title_key),
  FOREIGN KEY (job_location_key) REFERENCES location_dim(job_location_key)
);

-- Query: job titles per location
SELECT l.location, COUNT(DISTINCT jt.job_title_key) AS title_count
FROM job_posting_coverage_fact f
JOIN location_dim l ON f.job_location_key = l.job_location_key
JOIN job_title_dim jt ON f.job_title_key = jt.job_title_key
GROUP BY l.location;
```

## Notes

- **Mistake:** Treating factless tables as "pointless"—they're not lazy design; they're precise when relationships matter more than metrics.
- **Cardinality trap:** Without a factless table, joining transactional facts to multiple dimensions at different grain levels causes fan-out; factless tables sit at the intersection grain naturally.
- **Adjacent topic:** Bridge tables (many-to-many dimension resolution) use the same pattern; understand factless facts first to grasp why bridges exist.
- **Testing:** Verify your factless table hasn't introduced duplicate rows by counting distinct key pairs; a join to it should never inflate row counts.
- **Revisit:** Slowly-changing dimensions (SCD) on the dimensions referenced by your factless table; snapshot dates may belong on the factless table itself, not embedded in keys.
