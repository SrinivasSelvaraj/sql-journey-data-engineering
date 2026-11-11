---
date: 2026-11-11
phase: modelling
topic: Fact table grain: atomic facts vs pre-aggregated summaries
---

# Fact table grain: atomic facts vs pre-aggregated summaries

*Data modelling and warehousing*

## Concept

Fact table grain determines whether each row represents an atomic (lowest-level) business event or a pre-computed aggregate. An atomic fact captures the finest granularity of a business transaction—one row per job posting, one row per sales order line item—while pre-aggregated facts roll up data by time, geography, or category to reduce row count and query latency.

Grain matters because it controls what questions your fact table can answer without returning to source systems. Atomic facts are flexible: any aggregation can be derived from them. Pre-aggregated facts are rigid: if you stored daily salary totals by location, you cannot later answer "what was average salary by job title?" without rebuilding the table. Once you lose the atomic detail, you cannot recover it.

Without explicit grain definition, analysts either query the wrong table (getting incorrect totals from pre-aggregated data), or they ask you "why does this number not match my calculation?" because they didn't know a column was already summed. Grain ambiguity breaks trust in the warehouse and increases support burden.

## Practice

**Problem:** Your `job_postings_fact` table was loaded daily, and someone added a `applications_received` column by joining to an applications table and summing count(). Now queries are returning duplicated totals when analysts join `job_postings_fact` to a `departments_dim`, because salary and application counts are being multiplied across department rows. The grain is unclear: is each row one job posting, or is it one job posting per department?

**Solution:** Split into atomic and aggregated layers. Keep the atomic fact at job-posting grain, and create a separate pre-aggregated table for rolled-up metrics.

```sql
-- Atomic fact: one row per job posting (no aggregates)
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR,
    salary_year_avg DECIMAL,
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR
);

-- Pre-aggregated summary: one row per (date, location, title)
-- Explicit naming signals it is NOT atomic
CREATE TABLE job_postings_daily_agg (
    job_posted_date DATE,
    job_location VARCHAR,
    job_title_short VARCHAR,
    postings_count INT,
    avg_salary_year DECIMAL,
    pct_remote DECIMAL,
    PRIMARY KEY (job_posted_date, job_location, job_title_short)
);

-- Now joins are safe and grain is explicit
SELECT 
    d.department_name,
    COUNT(DISTINCT f.job_id) as unique_postings
FROM job_postings_fact f
JOIN departments_dim d ON f.job_location = d.location
GROUP BY d.department_name;
```

## Notes

- **Grain creep:** Never mix atomic and aggregated columns in one table. If you add `applications_received` (a sum), rename the table and document its grain explicitly, or revert to atomic grain by storing one row per (posting, application_batch).
- **Conformed dimensions:** Atomic facts should join cleanly to shared dimensions without multiplication. Pre-aggregated facts often use rolled-up or degenerate dimensions (e.g., `location_name` stored directly in the aggregate, not joined).
- **Slow-changing dimensions (SCD):** Atomic facts can point to a `dim` with SCD Type 2 (versioned rows). Pre-aggregated facts must decide: aggregate at the version level or collapse history? Ambiguity here causes audit failures.
- **Documentation is enforcement:** Use table naming (`_fact_atomic` vs `_summary_daily`), comments on the `applications_received` column ("SUM of applications by job_id"), and a data dictionary that lists grain for every fact table. Without it, the distinction evaporates.
- **Revisit:** Star schema normalization, dimensional modeling (Kimball), fact table types (transactional, periodic snapshot, accumulating snapshot), and query performance trade-offs (atomic flexibility vs. pre-aggregated speed).
