---
date: 2026-08-10
phase: modelling
topic: Grain: defining it and why it is the first decision
---

# Grain: defining it and why it is the first decision

*Data modelling and warehousing*

## Concept

Grain is the atomic level of detail in a fact table—the answer to "what does one row represent?" Without declaring it explicitly, every analyst interprets your schema differently. In `job_postings_fact`, the grain must be one row per unique job posting, not one row per job posting per day applied or per candidate viewed. The grain determines which dimensions you can attach and which metrics you can safely aggregate.

Grain is the first decision because it cascades into everything downstream. Wrong grain means you'll double-count, produce contradictory totals, or force analysts to write complex deduplication logic. It also dictates your primary key—which columns together uniquely identify one row. If you say the grain is "one row per job posting" but your key is `(job_id, application_date)`, you've lied and created a fact table no one can trust.

Getting grain right is impossible without understanding the business question. A hiring manager cares about "how many unique jobs are open?" while a recruiter cares about "how many applications per posting?" Same source data, different grains, different fact tables. Declare your grain upfront in comments or documentation so the next person (or future you) doesn't have to reverse-engineer it.

## Practice

**Problem:** You've been asked to track "average salary by location and posting date." Someone builds a query that joins `job_postings_fact` grouped by `job_location` and `job_posted_date`, sums salary, and divides by count. The result looks wrong—salaries are inflated. Why, and how do you fix the schema to prevent this?

**Root cause:** The grain is ambiguous. If one job is posted on the same date in the same location, and you group by date + location, you've lost the job-level detail. You're averaging across multiple salaries at once or accidentally duplicating rows.

**Solution:** Declare the grain explicitly and use a surrogate key:

```sql
-- GRAIN: One row per unique job posting
CREATE TABLE job_postings_fact (
    job_posting_sk INT PRIMARY KEY,  -- surrogate key
    job_id INT NOT NULL,             -- natural key component
    job_title_short VARCHAR(50),
    salary_year_avg DECIMAL(10,2),
    job_work_from_home BOOLEAN,
    job_posted_date DATE NOT NULL,   -- natural key component
    job_location VARCHAR(100) NOT NULL, -- natural key component
    UNIQUE(job_id, job_posted_date, job_location)
);

-- Now the correct query is unambiguous:
SELECT 
    job_location,
    job_posted_date,
    AVG(salary_year_avg) AS avg_salary,
    COUNT(DISTINCT job_posting_sk) AS job_count
FROM job_postings_fact
GROUP BY job_location, job_posted_date;
```

The surrogate key and UNIQUE constraint enforce the grain. Anyone querying this table now knows exactly what aggregation is safe.

## Notes

- **Confusing grain with dimensions:** Grain is not the same as "what columns do I have?" It's the answer to "what does one row represent?" Dimensions hang off that answer, not the other way around.

- **Missing the business context:** Grain must come from requirements, not data availability. If stakeholders ask "how many jobs are posted?" but your table's grain is "one row per posting per skill required," you're solving the wrong problem.

- **Surrogate keys hide sloppy thinking:** Don't use a surrogate key to paper over an unclear grain. The surrogate should enforce a natural key that expresses the grain. If you can't articulate the natural key, your grain isn't clear.

- **Grain and slowly changing dimensions:** If `job_title_short` or `job_location` can change for the same job ID, you've got an SCD (slowly changing dimension) problem. This affects whether those columns belong in the fact table or as a foreign key to a dimension table. Grain determines the answer.

- **Revisit cardinality:** Test your grain by asking: "If I remove one column from my primary key, do I still have unique rows?" If yes, that column isn't part of the grain—it's a dependent attribute and might belong elsewhere.
