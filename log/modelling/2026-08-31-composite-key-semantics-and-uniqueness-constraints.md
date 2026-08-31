---
date: 2026-08-31
phase: modelling
topic: Composite key semantics and uniqueness constraints
---

# Composite key semantics and uniqueness constraints

*Data modelling and warehousing*

## Concept

A composite key is a primary key made of two or more columns whose combined values must be unique across all rows. Unlike a single-column key, no individual column in the composite needs to be unique on its own—only the combination does. This is essential when a single attribute cannot reliably identify a row, but a combination can.

Composite keys matter most in dimensional models and fact tables where a row represents a specific event or relationship. Without proper composite key definition, you risk duplicate records silently entering your warehouse, causing inflated metrics, failed joins, and incorrect aggregations. The key also documents intent: it tells downstream users which column combinations define a "unique fact" and which columns are safe to use for deduplication.

A practical example: a job posting may have the same title and salary at different locations on different dates. `(job_id, job_posted_date)` or `(job_location, job_title_short, job_posted_date)` might be your true composite key depending on your business rule. Without naming it explicitly, a team member might assume `job_id` alone is unique, leading to logic errors.

## Practice

**Problem:** The `job_postings_fact` table needs to prevent duplicate postings for the same job at the same location on the same date, but allow the same job to be posted multiple times across different dates or locations. Which columns form the composite key, and how do you enforce it?

```sql
CREATE TABLE job_postings_fact (
  job_id INT NOT NULL,
  job_title_short VARCHAR(100) NOT NULL,
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE NOT NULL,
  job_location VARCHAR(100) NOT NULL,
  PRIMARY KEY (job_id, job_location, job_posted_date)
);

-- This prevents the same job_id at the same location on the same date
-- but allows: job_id=1 at NYC on 2024-01-01 AND job_id=1 at Boston on 2024-01-01
```

## Notes

- **Composite vs. surrogate keys:** Composite keys document business logic but can be verbose in joins; surrogate keys (single auto-increment ID) are faster but hide meaning. Often you need both: composite as a unique constraint, surrogate as clustered primary key.

- **Foreign key complexity:** Referencing a composite key table requires matching all columns in the child table—adds columns but enforces referential integrity precisely. Verify your staging pipelines populate all composite key columns before insert.

- **Null handling trap:** Most databases treat NULL as distinct (NULL ≠ NULL), so a composite key with one NULL column will allow duplicate rows. If any key column can be null, document this explicitly and consider a check constraint.

- **Grain definition:** The composite key *defines* the grain (level of detail) of your fact table. Document it in your schema metadata. It's the first thing a new analyst should check to understand what each row represents.

- **Revisit: natural vs. surrogate keys, slowly changing dimensions (SCD), and idempotent load logic.** Composite keys are load-critical—your insert logic must handle duplicates consistently.
