---
date: 2026-10-09
phase: modelling
topic: Mini-dimensions for attribute explosion in dimensions
---

# Mini-dimensions for attribute explosion in dimensions

*Data modelling and warehousing*

## Concept

A mini-dimension is a junk dimension that breaks out rapidly changing or sparse attributes into a separate table, leaving the fact table lean and queryable. Instead of adding 20 Boolean or low-cardinality columns directly to a fact table, you create a small dimension table that holds combinations of these attributes, then reference it via a foreign key. This keeps row width manageable and fact table scans fast.

The problem emerges when a dimension has attributes that change frequently (e.g., job posting visibility flags, work arrangements) or explode combinatorially (e.g., is_remote, is_contract, is_urgent, is_featured—2^4 = 16 combinations). Without a mini-dimension, you either denormalize heavily and repeat data, or add dozens of sparse columns that make queries hard to navigate and expensive to filter.

Mini-dimensions matter most in high-volume fact tables where you're scanning millions of rows. A fact table with 50 columns is slower to scan and harder to reason about than one with 10 columns plus a reference to a 50-row mini-dimension.

## Practice

**Problem:** Your `job_postings_fact` table has grown to include `job_work_from_home`, `job_is_urgent`, `job_is_featured`, and `job_is_contract`—four Boolean attributes that change daily and create 16 possible combinations. Queries that filter "show me remote, non-urgent jobs" must scan all rows and check multiple columns.

**Solution:**

```sql
-- Create mini-dimension for job posting attributes
CREATE TABLE job_posting_attributes_dim (
    job_attributes_key INT PRIMARY KEY,
    is_work_from_home BOOLEAN,
    is_urgent BOOLEAN,
    is_featured BOOLEAN,
    is_contract BOOLEAN
);

INSERT INTO job_posting_attributes_dim VALUES
    (1, FALSE, FALSE, FALSE, FALSE),
    (2, TRUE, FALSE, FALSE, FALSE),
    (3, FALSE, TRUE, FALSE, FALSE),
    -- ... (populate all 16 combinations)
    (16, TRUE, TRUE, TRUE, TRUE);

-- Refactored fact table (now only 7 columns instead of 10)
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR(100),
    salary_year_avg DECIMAL(10, 2),
    job_attributes_key INT REFERENCES job_posting_attributes_dim,
    job_posted_date DATE,
    job_location VARCHAR(100)
);

-- Query is now cleaner and faster
SELECT f.job_id, f.job_title_short, f.salary_year_avg
FROM job_postings_fact f
JOIN job_posting_attributes_dim a ON f.job_attributes_key = a.job_attributes_key
WHERE a.is_work_from_home = TRUE
  AND a.is_urgent = FALSE;
```

## Notes

- **Combinatorial explosion trap:** If you have 10 binary attributes, that's 1,024 possible combinations. Pre-compute only the combinations that actually exist in your data; don't create a Cartesian product.
- **Update frequency mismatch:** Mini-dimensions are ideal when the attributes change faster than the main dimension (e.g., job urgency flags flip hourly, but job titles are stable). If everything changes together, you may not need it.
- **Adjacent concept—Type 2 SCD:** If an attribute must be tracked historically (e.g., "job became urgent on date X"), consider a Type 2 SCD on the mini-dimension instead, with effective_date and end_date.
- **Common mistake—Over-normalization:** Don't create a mini-dimension for every attribute; reserve it for attributes that are sparse, low-cardinality, or change frequently. Single-attribute junk dimensions usually aren't worth the join.
- **Revisit shredded dimensions:** When you have many independent mini-dimensions referenced by the same fact table, ensure your query optimizer can handle the multiple joins efficiently; sometimes a single denormalized junk dimension is faster at scale.
