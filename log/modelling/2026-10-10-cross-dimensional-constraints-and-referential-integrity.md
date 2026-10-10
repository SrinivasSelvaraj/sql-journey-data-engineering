---
date: 2026-10-10
phase: modelling
topic: Cross-dimensional constraints and referential integrity
---

# Cross-dimensional constraints and referential integrity

*Data modelling and warehousing*

## Concept

Cross-dimensional constraints enforce business rules that span multiple tables—ensuring that facts reference valid dimension members and that relationships remain logically consistent. In a data warehouse, this means a fact record should never reference a job_title_id that doesn't exist in the job_titles dimension, or a location_id for a city that was deleted from the locations dimension. Without these constraints, your queries silently produce incomplete or misleading aggregations: sums that exclude orphaned records, counts that hide data quality issues, and dashboards that don't match source systems.

Referential integrity is the mechanism that guarantees every foreign key points to an existing primary key. It catches errors at load time rather than hiding them in downstream reports. In dimensional models, this becomes critical because dimension tables are the "source of truth" for business semantics—the job_title_short must always reference a valid, well-defined role; location must always map to a real geography. When integrity fails, you can't trust that "Marketing Manager" means the same thing everywhere in your warehouse.

## Practice

**Problem:** You're building a hiring analytics warehouse. The job_postings_fact table references job_title_short as text, but Marketing has three variants of the same role ("Marketing Manager," "Mktg Manager," "Marketing Mgr"). Analysts write conflicting queries. You also suspect some postings reference locations that no longer exist in your master location table, but you don't know which ones or how many.

```sql
-- Solution: Create a proper dimension and enforce referential integrity

-- 1. Create canonical job_titles dimension
CREATE TABLE job_titles_dim (
  job_title_id INT PRIMARY KEY,
  job_title_short VARCHAR(100) NOT NULL UNIQUE,
  job_title_full VARCHAR(255),
  job_category VARCHAR(50)
);

-- 2. Rebuild fact table with foreign key to dimension
CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_id INT NOT NULL,
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location_id INT NOT NULL,
  FOREIGN KEY (job_title_id) REFERENCES job_titles_dim(job_title_id),
  FOREIGN KEY (job_location_id) REFERENCES locations_dim(location_id)
);

-- 3. Identify orphaned records before migration
SELECT job_title_short, COUNT(*) 
FROM job_postings_fact_old jpo
LEFT JOIN job_titles_dim jd ON jpo.job_title_short = jd.job_title_short
WHERE jd.job_title_id IS NULL
GROUP BY job_title_short;

-- 4. Query now has guaranteed consistency
SELECT jd.job_category, COUNT(*) as posting_count
FROM job_postings_fact jpf
JOIN job_titles_dim jd ON jpf.job_title_id = jd.job_title_id
GROUP BY jd.job_category;
```

## Notes

- **Enforcement depends on the database:** traditional OLTP systems enforce constraints strictly; data warehouses often use them as documentation and validation logic instead, with ETL pipelines checking before load. Never assume your warehouse engine enforces FKs—test it.

- **Late-arriving dimensions** complicate this: a new job category added after postings are loaded needs a merge strategy. Plan your SCD (Slowly Changing Dimension) type before you build constraints.

- **Orphan data is a symptom:** finding records that violate referential integrity signals upstream data quality problems. Use validation queries to investigate, then fix the source, not the warehouse.

- **Connects to:** slowly changing dimensions (SCD types 1–5), conformed dimensions (ensuring job_title_id means the same thing across fact tables), and data quality frameworks (run FK checks as part of your post-load reconciliation).

- **Revisit:** whether you need bidirectional constraints (can a dimension row be deleted if facts reference it?), and whether your ETL tool has built-in referential integrity validation to skip manual checks.
