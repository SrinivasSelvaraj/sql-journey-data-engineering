---
date: 2026-10-27
phase: modelling
topic: Mixed grain fact tables and risks
---

# Mixed grain fact tables and risks

*Data modelling and warehousing*

## Concept

A mixed grain fact table combines facts at different levels of granularity in a single table—for example, mixing job-level attributes with company-level or market-level attributes. In `job_postings_fact`, if you include both `job_posted_date` (grain: individual posting) and `job_location` (grain: sometimes market, sometimes office), you risk storing redundant data and making aggregations ambiguous.

Without clear grain definition, queries become dangerous. When you SUM `salary_year_avg` grouped by `job_location`, are you summing salaries across all postings in that location, or averaging already-averaged values? Downstream users can't tell, and neither can they know which rows represent independent events versus denormalized repeats.

The risk crystallizes when a single job is posted to multiple locations or a location attribute changes mid-month. You either duplicate rows (bloating storage and creating aggregation traps) or lose information. Explicit grain—"one row per job posting"—prevents this ambiguity and makes the table self-documenting.

## Practice

**Problem:** `job_postings_fact` stores `job_location` as a single column, but jobs are often posted to multiple cities. Analysts sum `salary_year_avg` by location and get inflated figures because salaries repeat across location rows. A single $120k job posted to NYC and SF appears as $240k when grouped by location.

**Solution:** Separate the grains. Keep the fact table at job-posting grain and move multi-valued dimensions to a bridge table:

```sql
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR,
    salary_year_avg NUMERIC,
    job_work_from_home BOOLEAN,
    job_posted_date DATE
);

CREATE TABLE job_posting_locations (
    job_id INT,
    location_id INT,
    PRIMARY KEY (job_id, location_id),
    FOREIGN KEY (job_id) REFERENCES job_postings_fact(job_id)
);

-- Now safe: sum salary only once per job
SELECT l.location_id, COUNT(*) as posting_count, AVG(f.salary_year_avg)
FROM job_postings_fact f
JOIN job_posting_locations l ON f.job_id = l.job_id
GROUP BY l.location_id;
```

## Notes

- **Grain must be explicit in documentation**: state "one row per unique job posting" in the table's schema definition so new users don't guess wrong.
- **Denormalization temptation**: mixing grains feels efficient (fewer joins) until aggregations break; always choose clarity over join count.
- **Conformed dimensions matter here**: if `job_location` belongs to a separate `location_dim`, it naturally isolates the grain issue and makes the fact table cleaner.
- **Slowly changing dimensions amplify risk**: if job titles or locations change over time, a mixed-grain fact table becomes impossible to version correctly; use SCD Type 2 on dimensions instead.
- **Adjacent skill**: learn about fact table types (transaction, periodic snapshot, accumulating snapshot) to recognize when a single grain is genuinely impossible and when you need multiple fact tables instead.
