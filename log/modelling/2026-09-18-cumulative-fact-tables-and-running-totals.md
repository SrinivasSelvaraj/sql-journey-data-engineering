---
date: 2026-09-18
phase: modelling
topic: Cumulative fact tables and running totals
---

# Cumulative fact tables and running totals

*Data modelling and warehousing*

## Concept

A cumulative fact table (also called a snapshot fact table with running totals) records the state of a measure *up to and including* each transaction or time period, not just the delta. Instead of storing "5 new job postings today," you store "150 job postings exist as of today"—and tomorrow's row will show 155. This matters because downstream queries don't need to sum or recalculate from scratch; the cumulative value is already denormalized into each row.

Running totals become critical when you need to answer questions like "how many roles had we accumulated by month-end?" or "what was the hiring velocity on any given date?" without forcing analysts to write window functions or recursive CTEs every time. Without a cumulative design, you'll either have slow queries that aggregate backwards, or you'll end up answering the same calculation ten different ways across the organization.

The trade-off is storage: you store more rows (one per period per dimension combination) and must rebuild or append carefully. But the payoff is query simplicity and consistency—anyone can join and filter without worrying about double-counting or missing intermediate states.

## Practice

**Problem:** You need to track total job postings accumulated over time by location and work-from-home status. Analysts regularly ask "how many remote jobs had we posted cumulatively by the end of Q3?" and you want them to answer it in one SELECT without aggregation.

```sql
-- Cumulative fact table design
CREATE TABLE job_postings_cumulative_fact (
  job_posting_cumulative_key INT PRIMARY KEY,
  job_location_key INT,
  job_wfh_key INT,
  snapshot_date DATE,
  cumulative_job_count INT,
  cumulative_avg_salary DECIMAL(10,2),
  dbt_inserted_at TIMESTAMP
);

-- Daily snapshot logic (run once per day after posting data loads)
INSERT INTO job_postings_cumulative_fact
SELECT 
  ROW_NUMBER() OVER (ORDER BY snapshot_date, job_location_key, job_wfh_key),
  job_location_key,
  job_wfh_key,
  CURRENT_DATE AS snapshot_date,
  COUNT(DISTINCT job_id) AS cumulative_job_count,
  AVG(salary_year_avg) AS cumulative_avg_salary,
  CURRENT_TIMESTAMP
FROM (
  SELECT DISTINCT
    jd.job_location_key,
    CASE WHEN j.job_work_from_home THEN 1 ELSE 0 END AS job_wfh_key,
    j.job_id,
    j.salary_year_avg
  FROM job_postings_fact j
  LEFT JOIN job_location_dim jd ON j.job_location = jd.job_location
  WHERE j.job_posted_date <= CURRENT_DATE
) posting_history
GROUP BY job_location_key, job_wfh_key;

-- Query: cumulative remote jobs by Q3 end
SELECT job_location, cumulative_job_count
FROM job_postings_cumulative_fact cf
JOIN job_location_dim jd ON cf.job_location_key = jd.job_location_key
WHERE snapshot_date = '2024-09-30' AND cf.job_wfh_key = 1;
```

## Notes

- **Rebuild vs. append trap:** Decide upfront whether you rebuild the entire snapshot each day (simpler, idempotent) or append deltas (faster, but requires careful grain definition). Most teams choose rebuild for clarity.
- **Grain explosion:** Each unique combination of dimensions gets its own cumulative row. With 500 locations × 2 WFH states × 365 days, you'll have 365,000 rows—manageable, but monitor bloat as dimensions grow.
- **Connects to:** slowly changing dimensions (SCD Type 2), fact table granularity, and bridge tables for many-to-many relationships; also pairs well with dimensional modelling and conformed dimensions.
- **Watch the NULL problem:** Missing or NULL dimension keys will silently hide rows. Use a "Unknown" dimension entry or explicit filtering in documentation.
- **Revisit:** time-spine tables (calendar dimensions) and how to handle late-arriving facts that antedated your last snapshot run.
