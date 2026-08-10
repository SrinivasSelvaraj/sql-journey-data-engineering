---
date: 2026-08-10
phase: modelling
topic: Normalisation to 3NF and when to stop
---

# Normalisation to 3NF and when to stop

*Data modelling and warehousing*

## Concept

Normalisation to 3NF removes data redundancy by ensuring each non-key column depends on the primary key, the whole key, and nothing but the key. In data warehousing, you normalise dimensions and slowly-changing dimensions to avoid update anomalies and storage waste, while fact tables stay relatively denormalised for query performance. Stop normalising when further decomposition would require too many joins to answer business questions, or when the cost of joining outweighs the cost of storing redundant data. The practical rule: normalise until your schema is self-documenting—column meanings don't require institutional knowledge.

Without normalisation, you get insertion anomalies (can't add a new job title without a job posting), update anomalies (fixing a job title requires touching multiple rows), and deletion anomalies (removing all postings for a role loses the role definition). In a warehouse queried by many analysts, this means they either misinterpret stale or inconsistent data, or they ask you to fix inconsistencies.

## Practice

**Problem:** `job_postings_fact` mixes grain (one row per job posting) with dimension-like attributes (job_title_short repeats across postings). When job titles are renamed, you must update dozens of rows, risking inconsistency. New analysts don't know if "Senior Engineer" and "Sr. Engineer" are the same role.

**Solution:** Extract job titles and locations into dimension tables, then reference them by surrogate key.

```sql
CREATE TABLE dim_job_title (
    job_title_id INT PRIMARY KEY,
    job_title_short VARCHAR(100) NOT NULL UNIQUE,
    job_title_standardised VARCHAR(150),
    created_date DATE
);

CREATE TABLE dim_location (
    location_id INT PRIMARY KEY,
    location VARCHAR(100) NOT NULL UNIQUE,
    city VARCHAR(50),
    country VARCHAR(50),
    created_date DATE
);

CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_id INT NOT NULL REFERENCES dim_job_title(job_title_id),
    location_id INT NOT NULL REFERENCES dim_location(location_id),
    salary_year_avg DECIMAL(10,2),
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    created_date DATE
);
```

## Notes

- **Over-normalisation trap:** splitting into 4NF or 5NF for a warehouse often makes queries unreadable; analysts will avoid your schema and build their own denormalised views.
- **Fact vs. dimension:** dimensions normalise aggressively (3NF+); facts denormalise by design—keep commonly filtered/grouped columns in the fact table even if they repeat.
- **Slowly changing dimensions:** if job titles or locations change meaning over time, add `effective_date` and `end_date` to dimensions rather than updating; this preserves historical grain.
- **Self-documenting schema:** if a column's business meaning isn't obvious from its name or a data dictionary, normalisation hasn't solved your problem—the real issue is metadata governance.
- **Revisit:** Kimball dimensional modelling, surrogate keys vs. natural keys, conformed dimensions across multiple fact tables.
