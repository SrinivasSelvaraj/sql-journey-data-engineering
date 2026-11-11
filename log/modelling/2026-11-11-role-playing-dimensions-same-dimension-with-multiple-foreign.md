---
date: 2026-11-11
phase: modelling
topic: Role-playing dimensions: same dimension with multiple foreign keys
---

# Role-playing dimensions: same dimension with multiple foreign keys

*Data modelling and warehousing*

## Concept

A role-playing dimension occurs when a single dimension table is referenced multiple times by a fact table through different foreign keys, each representing a different logical role or context. For example, a fact table might join to a `location` dimension twice—once for "job posted location" and once for "job applicant location"—even though both reference the same underlying dimension structure.

This pattern matters because it eliminates redundant dimension tables and keeps your model DRY, but it requires explicit foreign key naming to make the business meaning clear. Without role-playing dimensions, you either duplicate the entire dimension (creating `location_posted` and `location_applied` tables) or use ambiguous column names that force analysts to read documentation or ask you which location a column represents.

The cost of missing this design choice is confusion at query time: analysts cannot tell whether `location_id` means where the job was posted or where the applicant is located, and your schema becomes harder to navigate and document.

## Practice

**Problem:** Your `job_postings_fact` table has both `job_location` (where posted) and `applicant_preferred_location` (where applicants want to work). Both are cities, but they mean different things. You need a single `location` dimension that plays both roles without ambiguity.

```sql
-- dimension table (used twice with different roles)
CREATE TABLE dim_location (
    location_id INT PRIMARY KEY,
    city VARCHAR(100),
    state VARCHAR(50),
    country VARCHAR(100)
);

-- fact table with role-playing foreign keys
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR(100),
    salary_year_avg INT,
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    posted_location_id INT,           -- FK role 1: where job is posted
    applicant_preferred_location_id INT,  -- FK role 2: where applicants want to work
    FOREIGN KEY (posted_location_id) REFERENCES dim_location(location_id),
    FOREIGN KEY (applicant_preferred_location_id) REFERENCES dim_location(location_id)
);

-- query example: find jobs posted in NYC where applicants also want to work in NYC
SELECT j.job_id, j.job_title_short, j.salary_year_avg
FROM job_postings_fact j
JOIN dim_location posted ON j.posted_location_id = posted.location_id
JOIN dim_location preferred ON j.applicant_preferred_location_id = preferred.location_id
WHERE posted.city = 'New York' 
  AND preferred.city = 'New York';
```

## Notes

- **Naming is everything:** use suffixes like `_posted_location_id` and `_preferred_location_id` instead of generic `location_id_1` and `location_id_2`. Your column names should tell the story; the SQL self-documents the business logic.

- **Joins require aliasing:** always alias the dimension table differently for each role (`posted` vs `preferred`) to avoid column ambiguity and make the query logic transparent to the next analyst.

- **Related pattern—bridge tables:** if a single fact record could have *multiple* values for the same dimension role (e.g., a job with 3 preferred locations), use a bridge/bridge table instead of role-playing—role-playing assumes one-to-one or many-to-one cardinality per role.

- **Snowflaking risk:** don't over-apply this pattern to avoid creating a tangled web of joins; use role-playing only when the same dimension truly represents different business contexts in one fact table.

- **Document your roles:** add a data dictionary entry that explicitly lists the roles each foreign key plays; this is not optional when role-playing dimensions exist.
