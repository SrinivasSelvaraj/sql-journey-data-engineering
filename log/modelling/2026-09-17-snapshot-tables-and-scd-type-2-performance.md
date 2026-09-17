---
date: 2026-09-17
phase: modelling
topic: Snapshot tables and SCD Type 2 performance
---

# Snapshot tables and SCD Type 2 performance

*Data modelling and warehousing*

## Concept

A **snapshot table** captures the complete state of a dimension or fact at a specific point in time—typically daily or weekly. **SCD Type 2** (Slowly Changing Dimension) maintains full historical records by adding `valid_from` and `valid_to` date columns and marking the current row as active. Together, they solve the problem of tracking *when* something changed and what the business state was at any query date.

Without snapshots or SCD Type 2, you overwrite historical data and lose the ability to answer retrospective questions: "What was the salary range for this job on March 15?" or "Which jobs were remote-eligible last quarter?" You're also forced to rebuild dimensions repeatedly or accept stale analytics. In high-velocity domains (hiring, pricing, inventory), this gap becomes critical within weeks.

The performance trade-off is real: snapshots and SCD Type 2 tables consume 2–5× more storage and require slightly more complex queries (date-range filters), but they eliminate the need for expensive late-arriving-dimension logic and make compliance audits feasible. The cost is justified when your business asks historical questions more than once.

## Practice

**Problem:** You need to report on job postings as they existed on any given date, accounting for updates to salary and remote-work status. Today, `job_postings_fact` is overwritten daily. You've lost the salary history for job_id=42.

**Solution: Implement SCD Type 2**

```sql
-- Create the historical dimension table
CREATE TABLE job_postings_scd2 (
    job_posting_sk INT PRIMARY KEY IDENTITY,
    job_id INT NOT NULL,
    job_title_short VARCHAR(100),
    salary_year_avg INT,
    job_work_from_home BOOLEAN,
    job_location VARCHAR(100),
    job_posted_date DATE NOT NULL,
    valid_from DATE NOT NULL,
    valid_to DATE NOT NULL DEFAULT '9999-12-31',
    is_current BOOLEAN NOT NULL DEFAULT TRUE
);

-- Query: "What was job_id=42's salary on 2024-03-15?"
SELECT salary_year_avg
  FROM job_postings_scd2
 WHERE job_id = 42
   AND job_posted_date <= '2024-03-15'
   AND valid_from <= '2024-03-15'
   AND valid_to >= '2024-03-15';

-- Insert a new snapshot (daily load logic)
INSERT INTO job_postings_scd2 (job_id, job_title_short, salary_year_avg, job_work_from_home, job_location, job_posted_date, valid_from, valid_to, is_current)
SELECT j.job_id, j.job_title_short, j.salary_year_avg, j.job_work_from_home, j.job_location, j.job_posted_date,
       CAST(GETDATE() AS DATE), '9999-12-31', 1
  FROM job_postings_fact j
  LEFT JOIN job_postings_scd2 scd ON j.job_id = scd.job_id AND scd.is_current = 1
 WHERE scd.job_id IS NULL
    OR (j.salary_year_avg <> scd.salary_year_avg OR j.job_work_from_home <> scd.job_work_from_home);

-- Update the previous record to mark it inactive
UPDATE job_postings_scd2
   SET valid_to = DATEADD(DAY, -1, CAST(GETDATE() AS DATE)), is_current = 0
 WHERE job_id IN (SELECT job_id FROM job_postings_fact WHERE ... [changed columns])
   AND is_current = 1;
```

## Notes

- **Date filter discipline:** Always include both `valid_from` and `valid_to` in WHERE clauses; forgetting `valid_to` returns expired rows and breaks historical accuracy.
- **Storage vs. query speed:** Snapshots bloat storage linearly but eliminate complex temporal joins; acceptable for fact tables under 500M rows/day; consider partitioning by `valid_from` for large tables.
- **Surrogate keys matter:** Use `job_posting_sk` (not `job_id`) in fact tables; `job_id` is the business key and can appear multiple times across time periods.
- **Related: Fact table grain:** Decide early whether your fact is "job posting state at a point in time" or "job posting events"; this determines whether you snapshot or log transactions.
- **Test the edge case:** Rows valid on day X but not day X+1; write unit tests for the 24-hour boundary where `valid_to` switches from '9999-12-31' to yesterday.
