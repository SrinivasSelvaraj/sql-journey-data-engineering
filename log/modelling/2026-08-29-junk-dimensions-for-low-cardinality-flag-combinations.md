---
date: 2026-08-29
phase: modelling
topic: Junk dimensions for low-cardinality flag combinations
---

# Junk dimensions for low-cardinality flag combinations

*Data modelling and warehousing*

## Concept

A junk dimension is a helper dimension table that groups together low-cardinality flags and attributes that don't warrant their own dimension table. Instead of scattering boolean columns across a fact table, you consolidate them into a single dimension with a surrogate key. For example, a `work_from_home`, `visa_sponsored`, and `has_relocation_assistance` flag might combine into a single `job_flexibility_dim` with 8 possible rows (2³ combinations).

This matters when your fact table would otherwise have 5+ boolean or small categorical columns that clutter queries and make it unclear whether `job_work_from_home = TRUE` means "fully remote" or "hybrid." Without a junk dimension, analysts repeat the same flag definitions in every query, business logic lives in SQL comments, and renames become migration nightmares.

Without consolidation, you also lose query clarity—does `WHERE job_work_from_home = 1 AND job_visa_sponsored = 1` mean the posting matches both conditions, or are they mutually exclusive? A junk dimension makes this explicit by assigning a meaningful `flexibility_dim_key` to each valid combination, turning scattered flags into a single, documented join.

## Practice

**Problem:** Your `job_postings_fact` table has `job_work_from_home` and three other boolean flags (`visa_sponsored`, `has_relocation`, `internship_eligible`). Queries are inconsistent—some teams filter `job_work_from_home = TRUE`, others use strings like `'Remote'`. You need a single source of truth.

**Solution:**

```sql
-- Create junk dimension
CREATE TABLE job_flexibility_dim (
  flexibility_dim_key INT PRIMARY KEY,
  work_from_home BOOLEAN,
  visa_sponsored BOOLEAN,
  has_relocation BOOLEAN,
  internship_eligible BOOLEAN,
  flexibility_description VARCHAR(100)
);

INSERT INTO job_flexibility_dim VALUES
(1, FALSE, FALSE, FALSE, FALSE, 'On-site, no sponsorship'),
(2, FALSE, FALSE, FALSE, TRUE, 'On-site, internship eligible'),
(3, TRUE, FALSE, FALSE, FALSE, 'Remote only'),
(4, TRUE, TRUE, FALSE, FALSE, 'Remote, visa sponsored'),
-- ... etc for all 16 combinations

-- Refactor fact table
ALTER TABLE job_postings_fact 
DROP COLUMN job_work_from_home, job_visa_sponsored, job_has_relocation, job_internship_eligible;

ALTER TABLE job_postings_fact 
ADD COLUMN flexibility_dim_key INT REFERENCES job_flexibility_dim(flexibility_dim_key);

-- Now queries are consistent and self-documenting
SELECT f.job_title_short, COUNT(*) as count
FROM job_postings_fact f
JOIN job_flexibility_dim d ON f.flexibility_dim_key = d.flexibility_dim_key
WHERE d.flexibility_description LIKE '%visa%'
GROUP BY f.job_title_short;
```

## Notes

- **Cardinality check:** Only use junk dimensions when the flag combination produces ≤50–100 rows; beyond that, break into separate dimensions or leave flags in the fact table.
- **Naming trap:** Don't call it `flags_dim` or `misc_dim`—use a domain name like `job_flexibility_dim` or `employment_terms_dim` so analysts know what it represents.
- **Maintenance cost:** Every new flag requires backfilling all historical combinations and adding new rows; document this decision early so teams don't add flags ad-hoc.
- **Connects to:** Conformed dimensions (reusing the same `flexibility_dim_key` across multiple fact tables), slowly changing dimensions (when flag definitions evolve), and bridge tables (if a job posting can have *multiple* flexibility profiles).
- **Revisit:** Consider whether a simple lookup table or materialized view might be clearer than a formal dimension join—junk dimensions shine in star schemas but can be overkill in denormalized reporting layers.
