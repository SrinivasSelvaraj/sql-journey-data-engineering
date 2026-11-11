---
date: 2026-11-11
phase: modelling
topic: Additive, semi-additive and non-additive facts
---

# Additive, semi-additive and non-additive facts

*Data modelling and warehousing*

## Concept

In a fact table, facts fall into three categories based on how they behave when aggregated. **Additive facts** sum meaningfully across all dimensions (revenue, quantity sold, page views). **Semi-additive facts** sum meaningfully across *some* dimensions but not others (account balance, inventory level—you can sum across products but not time). **Non-additive facts** never sum meaningfully and must be aggregated via count, average, or dimension-specific logic (ratios, percentages, unit prices).

Misclassifying facts breaks self-service analytics. A team member querying your warehouse might sum `salary_year_avg` across all jobs expecting a meaningful metric, when that number is actually semi-additive (valid only when grouped by job, not across jobs). Without clear documentation or schema design that prevents nonsense queries, they'll get an inflated or meaningless result and lose trust in the data.

The solution is to flag semi- and non-additive facts explicitly in column naming, add lineage documentation, or move them to a separate dimension table. This forces conscious choices: do I *really* want to aggregate this, and if so, which dimensions are valid?

## Practice

**Problem:** Your `job_postings_fact` table includes `salary_year_avg`. A junior analyst sums it across all 50,000 jobs to calculate "total salary" as a KPI metric, then reports it to leadership.

Why this is broken: `salary_year_avg` is **non-additive**. Summing it produces a nonsensical number. The analyst should have counted jobs in salary bands, or averaged by location, or used a proper metric like "median salary by role."

**Solution:**

```sql
-- Refactor: move salary to a dimension or clearly separate it
CREATE TABLE job_salary_dim (
  salary_key INT PRIMARY KEY,
  salary_year_avg INT,
  salary_band VARCHAR(50),
  currency VARCHAR(3)
);

CREATE TABLE job_postings_fact (
  job_id INT PRIMARY KEY,
  job_title_key INT,
  salary_key INT,  -- FK, not for direct summation
  job_location_key INT,
  job_posted_date DATE,
  job_work_from_home BOOLEAN,
  postings_count INT  -- additive: count of postings
  FOREIGN KEY (salary_key) REFERENCES job_salary_dim(salary_key)
);

-- Correct query pattern:
SELECT 
  salary_band,
  COUNT(*) AS posting_count,
  AVG(salary_year_avg) AS avg_salary  -- explicit aggregation
FROM job_postings_fact jpf
JOIN job_salary_dim sd ON jpf.salary_key = sd.salary_key
GROUP BY salary_band;
```

## Notes

- **Don't bury semi/non-additive facts in fact tables without context.** Use column naming (`_avg`, `_pct`, `_balance`) or a `fact_type` metadata table to signal aggregation rules.
- **Common mistake:** Treating all numeric columns as additive. Boolean flags like `job_work_from_home` are non-additive (summing them is meaningless; count them instead).
- **Dimension tables are your friend for non-additive data.** Move unit prices, ratios, and codes to dimensions; keep only counts and measurable events in facts.
- **Connects to:** Conformed dimensions (shared lookups reduce ambiguity), fact table grains (if grain is "one row per job posting," salary becomes inherently non-additive across jobs), and slowly changing dimensions (salary bands evolve).
- **Revisit if:** You find analysts writing `SUM(percentage)` or summing dates. That's a sign your schema isn't communicating aggregation rules clearly enough.
