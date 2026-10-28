---
date: 2026-10-28
phase: modelling
topic: Slowly changing dimensions type 4 history
---

# Slowly changing dimensions type 4 history

*Data modelling and warehousing*

## Concept

Type 4 SCD (Slowly Changing Dimension) uses a **dedicated history table** to track changes while keeping the main dimension table as a simple, fast current-state lookup. When a dimension attribute changes (e.g., a job title gets reclassified), you insert a new row into the history table with the old value, effective dates, and a flag marking it as historical. The main dimension table updates to the new current value only.

This matters when you need both fast queries on current state *and* accurate historical context for analysis. Without it, you either overwrite history (losing it entirely) or bloat your main dimension with validity dates on every column, slowing down the 80% of queries that only care about "what is it now?" A classic case: a company's job_title changes from "Junior Developer" to "Software Engineer I"—your reports need to know which one was active when each applicant applied.

Breaking without it means either your dashboards show inconsistent job titles (because you updated in place), or your fact table queries become complex, joining through date ranges just to get the current name. Version history disappears or becomes scattered.

## Practice

**Problem:** Job postings get reclassified over time—a role listed as "Data Analyst" might be recoded as "Analytics Engineer" three months later after the company restructures. You need to report on hiring trends *by the title as it was at posting time*, not by today's title.

```sql
-- Main dimension table (current state only)
CREATE TABLE job_dim (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  job_location VARCHAR(100),
  last_updated DATE
);

-- Type 4 History table
CREATE TABLE job_dim_history (
  job_history_id INT PRIMARY KEY AUTO_INCREMENT,
  job_id INT NOT NULL,
  job_title_short VARCHAR(100),
  job_location VARCHAR(100),
  effective_date DATE,
  end_date DATE,
  is_current BOOLEAN,
  FOREIGN KEY (job_id) REFERENCES job_dim(job_id)
);

-- When job_title changes for job_id=42, insert old value to history
INSERT INTO job_dim_history (job_id, job_title_short, job_location, effective_date, end_date, is_current)
VALUES (42, 'Data Analyst', 'NYC', '2024-01-15', '2024-04-30', FALSE);

-- Update current dimension
UPDATE job_dim SET job_title_short = 'Analytics Engineer', last_updated = '2024-05-01' WHERE job_id = 42;

-- Query: applications by job title *as it was* at posting time
SELECT 
  h.job_title_short,
  COUNT(a.application_id) as applications
FROM job_postings_fact a
JOIN job_dim_history h 
  ON a.job_id = h.job_id 
  AND a.job_posted_date BETWEEN h.effective_date AND h.end_date
GROUP BY h.job_title_short;
```

## Notes

- **Don't join history on every query by default**—use it only when you need historical accuracy; most dashboards query the main dimension directly for speed.
- **Confusing Type 4 with Type 2:** Type 2 (versioned rows in the main dimension) adds rows; Type 4 keeps dimension lean and moves history elsewhere. Pick based on query patterns, not principle.
- **Missing end_date logic:** Always populate `end_date` when inserting old records, or use NULL to mean "still open"—ambiguous dates cause silent bugs in range joins.
- **is_current flag vs. date ranges:** Both work, but a boolean flag is faster for "give me current state" queries; keep both if your warehouse supports it.
- **Connects to:** fact table grain (must align with when history was valid), slowly changing dimension reporting (temporal queries), and audit tables (which are simpler and don't need dimension logic).
