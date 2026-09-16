---
date: 2026-09-16
phase: modelling
topic: Bridge tables for many-to-many dimensions
---

# Bridge tables for many-to-many dimensions

*Data modelling and warehousing*

## Concept

A bridge table (or junction table) resolves many-to-many relationships between dimensions in a star schema. Without it, you either duplicate rows unnecessarily or lose information. For example, a job posting might require multiple skills, and a skill might appear across multiple job postings—neither a pure one-to-many nor a clean attribute fit.

In a dimensional model, you want facts at a single grain (one row = one job posting). If you embed multiple skills directly into the fact table as comma-separated values or arrays, you sacrifice atomicity and make aggregations painful ("how many postings require Python?" becomes a substring search). A bridge table sits between your fact and dimension, letting you join through it without inflating fact cardinality.

Without a bridge table, teams either ask you how to query many-to-many relationships, or they write fragile, slow queries that unnest strings or rely on fuzzy logic. The bridge table is the structural answer: it says "these two entities relate many-to-many" in a language the schema itself speaks.

## Practice

**Problem:** `job_postings_fact` should let you filter by skill and aggregate job counts per skill. Currently, there's no way to store "this job requires Python, SQL, and AWS" without denormalizing or adding an array column that breaks GROUP BY logic.

**Solution:**

```sql
-- Bridge table
CREATE TABLE job_skill_bridge (
    job_id INT,
    skill_id INT,
    skill_required_level VARCHAR(20),  -- e.g., 'beginner', 'expert'
    PRIMARY KEY (job_id, skill_id),
    FOREIGN KEY (job_id) REFERENCES job_postings_fact(job_id),
    FOREIGN KEY (skill_id) REFERENCES skills_dim(skill_id)
);

-- Query: count postings per skill
SELECT 
    s.skill_name,
    COUNT(DISTINCT b.job_id) AS posting_count,
    ROUND(AVG(f.salary_year_avg), 0) AS avg_salary
FROM job_skill_bridge b
INNER JOIN skills_dim s ON b.skill_id = s.skill_id
INNER JOIN job_postings_fact f ON b.job_id = f.job_id
WHERE b.skill_required_level = 'expert'
GROUP BY s.skill_name
ORDER BY posting_count DESC;
```

## Notes

- **Cardinality mistake:** Joining a fact table directly to a bridge table without aggregating first can inflate row counts; always consider whether you're double-counting metrics.
- **Bridge table grain:** Keep the bridge table's primary key as narrow as possible (usually just the two foreign keys). Add attributes only if they're specific to that relationship, not to either dimension alone.
- **Snowflaking trade-off:** A bridge table is a mild form of snowflaking (denormalizing the star). It complicates queries slightly but preserves fact grain and atomic dimensions—worth it for true many-to-many cardinality.
- **Adjacent: slowly changing dimensions (SCD):** If skill requirements or level change over time, add effective_date to the bridge table and apply SCD Type 2 logic.
- **Revisit:** Test bridge table queries with large fact tables (millions of rows) to confirm join performance; consider materializing aggregates if the bridge becomes a bottleneck.
