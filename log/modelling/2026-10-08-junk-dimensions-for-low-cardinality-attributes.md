---
date: 2026-10-08
phase: modelling
topic: Junk dimensions for low-cardinality attributes
---

# Junk dimensions for low-cardinality attributes

*Data modelling and warehousing*

## Concept

A junk dimension is a single dimension table that collects low-cardinality Boolean, flag, or small-domain attributes that don't warrant their own dimension table. Instead of creating separate dimension tables for every binary or small-set attribute, you group them into one denormalized junk dimension and join it via a foreign key in your fact table.

This matters because every dimension you add increases join complexity and cognitive load for analysts. If you create individual dimensions for `is_work_from_home`, `is_urgent`, and `is_internal_posting`—each with only 2–4 rows—you're inflating your schema with unnecessary tables. A junk dimension eliminates this noise while keeping your fact table clean and your queries readable.

Without junk dimensions, you either end up with dozens of pointless single-column dimension tables cluttering your schema documentation, or you embed flags directly in the fact table (mixing dimensions and measures). Both approaches break self-service: analysts either get lost in a forest of tiny tables or can't distinguish which columns are descriptive vs. numeric.

## Practice

**Problem:** Your `job_postings_fact` table has three low-cardinality attributes: `job_work_from_home` (Boolean), and two derived flags you need—`is_urgent` (Boolean) and `salary_visible` (Boolean). Without a junk dimension, you'd either add three columns to the fact table (mixing business logic) or create three separate dimension tables (clutter). How do you model this cleanly?

**Solution:**

```sql
-- Create the junk dimension
CREATE TABLE job_posting_attributes_dim (
    job_attributes_key INT PRIMARY KEY,
    is_work_from_home BOOLEAN,
    is_urgent BOOLEAN,
    salary_visible BOOLEAN,
    UNIQUE(is_work_from_home, is_urgent, salary_visible)
);

-- Populate with all combinations
INSERT INTO job_posting_attributes_dim VALUES
(1, FALSE, FALSE, FALSE),
(2, FALSE, FALSE, TRUE),
(3, FALSE, TRUE, FALSE),
(4, FALSE, TRUE, TRUE),
(5, TRUE, FALSE, FALSE),
(6, TRUE, FALSE, TRUE),
(7, TRUE, TRUE, FALSE),
(8, TRUE, TRUE, TRUE);

-- Refactored fact table
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_attributes_key INT NOT NULL,
    job_title_short VARCHAR(100),
    salary_year_avg DECIMAL(10, 2),
    job_posted_date DATE,
    job_location VARCHAR(100),
    FOREIGN KEY (job_attributes_key) REFERENCES job_posting_attributes_dim(job_attributes_key)
);

-- Query example
SELECT 
    f.job_id,
    f.job_title_short,
    f.salary_year_avg,
    d.is_work_from_home,
    d.is_urgent
FROM job_postings_fact f
JOIN job_posting_attributes_dim d ON f.job_attributes_key = d.job_attributes_key
WHERE d.is_urgent = TRUE AND d.salary_visible = TRUE;
```

## Notes

- **Cardinality threshold:** Use junk dimensions when individual attributes have ≤10 unique values combined. Beyond that (or if attributes grow independently), split into proper dimensions.
- **Pre-populate combinations:** Generate all valid combinations upfront; avoid NULL keys or sparse dimension tables. Use a UNIQUE constraint to enforce consistency.
- **Adjacent topic—Conformed dimensions:** A junk dimension is one flavor of denormalization. Understand conformed dimensions (shared across fact tables) to recognize when to centralize vs. create fact-specific junk dimensions.
- **Common mistake:** Lumping unrelated low-cardinality attributes together just because they're small. If `is_compliant_with_eeo` and `is_remote` have different change frequencies or business meanings, keep them separate.
- **Revisit when:** Schema grows and your junk dimension exceeds 20–30 rows, or when a single flag becomes a primary filter in every query—both signals it deserves its own dimension table.
