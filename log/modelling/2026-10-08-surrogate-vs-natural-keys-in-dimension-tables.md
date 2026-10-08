---
date: 2026-10-08
phase: modelling
topic: Surrogate vs natural keys in dimension tables
---

# Surrogate vs natural keys in dimension tables

*Data modelling and warehousing*

## Concept

A **surrogate key** is a system-generated identifier (usually an auto-incrementing integer or UUID) with no business meaning; a **natural key** is composed of one or more business attributes that uniquely identify a row. In dimension tables, surrogate keys become the primary key and foreign key reference in fact tables, while natural keys (if they exist) become alternate unique constraints.

Surrogate keys matter because natural keys can change. A job title like "Senior Engineer" might be rebranded to "Principal Engineer"; a customer's email might be updated; a location code might be consolidated. When a natural key changes, you face a choice: update old fact records (breaking history) or keep stale dimensional data. Surrogate keys decouple the dimension's identity from its attributes, letting you handle slowly changing dimensions (SCD Type 1, 2, or 3) elegantly.

Without surrogate keys, you either repeat natural key tuples across fact tables (storage bloat), lose change history, or create brittle foreign keys that break when business rules shift. Surrogate keys also simplify joins and improve query readability—a fact table references `job_posting_dim_id`, not a composite `(company_id, location_id, job_category_id)`.

## Practice

**Problem:** Your `job_postings_fact` uses `job_title_short` as a foreign key, but the marketing team decides to rename "ML Engineer" to "Machine Learning Engineer." Hundreds of fact rows reference the old value. How do you maintain history without corrupting the fact table?

**Solution:** Introduce a surrogate key in a new `job_titles_dim` dimension:

```sql
CREATE TABLE job_titles_dim (
  job_title_dim_id INT PRIMARY KEY AUTO_INCREMENT,
  job_title_short VARCHAR(100) NOT NULL,
  job_title_full VARCHAR(255),
  effective_date DATE NOT NULL,
  end_date DATE,
  is_current BOOLEAN DEFAULT TRUE,
  UNIQUE KEY uk_title_dates (job_title_short, effective_date)
);

CREATE TABLE job_postings_fact (
  job_posting_id BIGINT PRIMARY KEY,
  job_title_dim_id INT NOT NULL,
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100),
  FOREIGN KEY (job_title_dim_id) REFERENCES job_titles_dim(job_title_dim_id)
);

-- Insert renamed title as new row (SCD Type 2)
INSERT INTO job_titles_dim (job_title_short, job_title_full, effective_date, is_current)
VALUES ('Machine Learning Engineer', 'Machine Learning Engineer', '2024-01-15', TRUE);

-- Mark old title as historical
UPDATE job_titles_dim
SET is_current = FALSE, end_date = '2024-01-14'
WHERE job_title_short = 'ML Engineer' AND is_current = TRUE;

-- Old fact rows still point to old dim ID; new postings point to new dim ID
SELECT jpf.job_posting_id, jtd.job_title_short, jpf.salary_year_avg
FROM job_postings_fact jpf
JOIN job_titles_dim jtd ON jpf.job_title_dim_id = jtd.job_title_dim_id;
```

## Notes

- **Mistake:** Using natural keys as fact table FKs and assuming they never change. Business rules always drift; plan for it.
- **SCD strategies:** Type 1 (overwrite) loses history; Type 2 (add rows with date ranges) preserves it; Type 3 (add columns) offers middle ground. Choose based on how often attributes change and whether analysts need to see "what was true on date X."
- **Alternate key:** Always index the natural key in your dimension (e.g., `UNIQUE KEY uk_job_title_short`) so you can join on it during loads without scanning the whole table.
- **Grain clarity:** Surrogate keys make the dimension's grain explicit. If `job_titles_dim` has one row per title, document it; if it's one row per title *per effective period*, that changes join logic.
- **Related:** Revisit slowly changing dimensions, dimension conformation (shared keys across marts), and fact table grain definition—all rely on consistent surrogate key design.
