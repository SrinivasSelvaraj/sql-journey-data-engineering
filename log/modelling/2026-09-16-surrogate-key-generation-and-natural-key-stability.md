---
date: 2026-09-16
phase: modelling
topic: Surrogate key generation and natural key stability
---

# Surrogate key generation and natural key stability

*Data modelling and warehousing*

## Concept

A **surrogate key** is a system-generated identifier (typically an auto-incrementing integer or UUID) assigned to each row in a dimension table, independent of the business data itself. A **natural key** is the combination of business attributes that uniquely identify an entity (e.g., job title + location + posting date). Surrogate keys matter because natural keys are fragile: job titles change spelling, locations get recoded, and dates shift with business rules. Without a stable surrogate key, your fact tables break when you try to join to slowly-changing dimensions.

The core problem: if you join `job_postings_fact` directly on `(job_title_short, job_location)`, and someone corrects "Senior Sofware Engineer" to "Senior Software Engineer," your historical joins silently produce wrong aggregates. The old fact records no longer match the updated dimension row. A surrogate key (`job_id`) pins the relationship, while a bridge table or type-2 SCD (slowly changing dimension) row captures what changed and when.

Stability is semantic clarity: downstream users see `job_id = 42` means a specific role at a point in time, not a brittle textual match that depends on whoever last touched the ETL.

## Practice

**Problem:** Your analytics team wants to trend salary by job title over time. Natural key `(job_title_short, job_location)` is tempting but fails when "Data Scientist" gets renamed to "Data Scientist (ML Focus)". Historical fact records still hold the old title string and won't join to the renamed dimension row.

```sql
-- Solution: surrogate key + type-2 SCD

-- Dimension table with surrogate key and validity window
CREATE TABLE job_dim (
    job_sk INT PRIMARY KEY,
    job_title_short VARCHAR(100),
    job_location VARCHAR(100),
    salary_year_avg DECIMAL(10, 2),
    job_work_from_home BOOLEAN,
    effective_date DATE,
    end_date DATE,
    is_current BOOLEAN
);

-- Fact table references surrogate key, not natural key
CREATE TABLE job_postings_fact (
    job_sk INT REFERENCES job_dim(job_sk),
    job_posted_date DATE,
    applications_count INT,
    FOREIGN KEY (job_sk) REFERENCES job_dim(job_sk)
);

-- Query salary trends safely: all old and new title versions tracked
SELECT 
    jd.job_title_short,
    jd.effective_date,
    AVG(jd.salary_year_avg) AS avg_salary
FROM job_postings_fact jpf
JOIN job_dim jd ON jpf.job_sk = jd.job_sk
WHERE jd.is_current = TRUE
GROUP BY jd.job_title_short, jd.effective_date
ORDER BY jd.job_title_short, jd.effective_date;
```

## Notes

- **Don't use natural keys in fact tables.** It couples your facts to dimension semantics and breaks incrementally. Always reference the surrogate key.
- **Type-2 SCD (slowly changing dimension)** is the standard pattern: insert a new row with a new surrogate key when a dimension attribute changes, set `end_date` on the old row. This preserves history without breaking joins.
- **Surrogate keys can be generated at ingestion** (database sequence, UUID, or hash of natural key + source system) but must be *stable*—the same natural key must always map to the same surrogate in repeat loads.
- **Bridge tables** handle many-to-many dimensions (e.g., a job posting in multiple locations). Use them instead of denormalizing; they keep your fact grain clean.
- **Revisit:** Grain definition (what one row represents), conformed dimensions (shared across fact tables), and whether you need type-1 (overwrite) vs. type-2 (history) for each slowly-changing attribute.
