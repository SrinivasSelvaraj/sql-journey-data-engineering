---
date: 2026-08-10
phase: modelling
topic: Star schema: facts and dimensions
---

# Star schema: facts and dimensions

*Data modelling and warehousing*

## Concept

A star schema separates business data into **fact tables** (measurable events: sales, clicks, job postings) and **dimension tables** (descriptive attributes: dates, locations, job titles). The fact table sits at the center with foreign keys pointing outward to dimensions, forming a star shape. This design eliminates ambiguity: every column has a single, well-understood meaning because dimensions define attributes once, and facts record only what happened.

Star schemas matter when your team grows beyond you. Without them, analysts query raw tables and invent their own definitions—one person's "remote job" might be another's "hybrid." When facts and dimensions are separated, a `dim_job_category` table becomes the source of truth; everyone uses the same category codes and labels. This prevents conflicting reports and the "which number is correct?" conversations that waste weeks.

The schema breaks down when you denormalize facts too aggressively (storing job title text directly instead of a key) or fail to create proper dimensions (leaving location as free text in the fact table). You lose reusability, bloat the fact table, and regain the ambiguity you were trying to escape.

## Practice

**Problem:** The `job_postings_fact` table mixes raw data with denormalized text. `job_title_short` and `job_location` are strings, so analysts can't easily group by location without guessing at spelling variations, and the table grows fat with repeated titles. How do you restructure this into a proper star schema?

```sql
-- Dimension tables (single source of truth for attributes)
CREATE TABLE dim_job_title (
    job_title_id SERIAL PRIMARY KEY,
    job_title_short VARCHAR(100),
    job_category VARCHAR(50)
);

CREATE TABLE dim_location (
    location_id SERIAL PRIMARY KEY,
    location_name VARCHAR(100),
    city VARCHAR(50),
    country VARCHAR(50)
);

CREATE TABLE dim_date (
    date_id SERIAL PRIMARY KEY,
    date DATE,
    year INT,
    month INT,
    quarter INT
);

-- Fact table (only measures and foreign keys)
CREATE TABLE fact_job_postings (
    job_posting_id SERIAL PRIMARY KEY,
    job_title_id INT REFERENCES dim_job_title(job_title_id),
    location_id INT REFERENCES dim_location(location_id),
    posted_date_id INT REFERENCES dim_date(date_id),
    salary_year_avg DECIMAL(10, 2),
    job_work_from_home BOOLEAN
);

-- Query: average salary by location and job category (no ambiguity)
SELECT 
    dl.location_name,
    djt.job_category,
    AVG(fjp.salary_year_avg) AS avg_salary
FROM fact_job_postings fjp
JOIN dim_location dl ON fjp.location_id = dl.location_id
JOIN dim_job_title djt ON fjp.job_title_id = djt.job_title_id
GROUP BY dl.location_name, djt.job_category;
```

## Notes

- **Over-normalization trap:** Don't create a dimension for every column. Dimensions should represent business entities (locations, products, people); trivial flags like `work_from_home` can stay in facts.
- **Slowly changing dimensions:** Job titles and locations shift over time. Decide: do you track history (version the dimension row) or overwrite? This choice affects how you join old facts to current definitions.
- **Conformed dimensions:** If multiple fact tables exist (job postings, applications, hires), they should all reference the *same* `dim_location` and `dim_job_title` tables. This enables cross-fact analysis and enforces consistency.
- **Surrogate keys matter:** Use numeric IDs (`location_id`) instead of strings in facts. They compress storage, speed joins, and decouple facts from dimension changes (e.g., renaming a city doesn't cascade).
- **Related schemas:** Snowflake schemas (normalize dimensions further), data vaults (add metadata tracking), and galaxy schemas (multiple fact tables) are variations for different maturity levels and query patterns.
