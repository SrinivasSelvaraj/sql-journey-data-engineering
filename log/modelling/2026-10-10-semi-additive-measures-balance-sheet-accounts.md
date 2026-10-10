---
date: 2026-10-10
phase: modelling
topic: Semi-additive measures: balance sheet accounts
---

# Semi-additive measures: balance sheet accounts

*Data modelling and warehousing*

## Concept

Semi-additive measures are numeric facts that can be summed across some dimensions but not others. Balance sheet accounts—cash, inventory, accounts receivable—exemplify this perfectly: summing a monthly ending balance across months gives nonsense, but summing balances across locations on the same date is valid. Without recognizing semi-additivity, you build dashboards that silently produce wrong answers: a "total cash" metric across a year appears to be twelve times higher than reality.

In fact tables, semi-additive measures require a snapshot grain—typically one row per entity per date. A job_postings_fact recording salary_year_avg works only if you're clear about *when* that salary was recorded; if you aggregate by date range without understanding the measure's temporal nature, you'll double-count or misrepresent averages. The schema must enforce this grain through primary keys and clear documentation.

The fix is intentional design: declare which dimensions allow aggregation (location, department, job category) and which don't (time). Use fact table granularity as your contract—if it's "one row per job per posting date," then salary_year_avg can only be meaningfully averaged or filtered by date, never summed across dates.

## Practice

**Problem:** You have job_postings_fact and want to report "average salary across all active postings in Q4 2024." A junior analyst sums all salary_year_avg values and divides by row count, but some postings appear multiple times (reposted), inflating the numerator.

**Solution:** Snapshot the fact table to one row per job per distinct posted_date, then aggregate safely:

```sql
WITH job_snapshot AS (
  SELECT 
    job_id,
    job_posted_date,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_location,
    ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY job_posted_date DESC) AS rn
  FROM job_postings_fact
  WHERE job_posted_date >= '2024-10-01' AND job_posted_date < '2025-01-01'
)
SELECT 
  ROUND(AVG(salary_year_avg), 2) AS avg_salary_q4,
  COUNT(DISTINCT job_id) AS unique_postings
FROM job_snapshot
WHERE rn = 1;
```

## Notes

- **Confusing semi-additive with non-additive:** Non-additive facts (like ratios or percentages) never roll up; semi-additive facts roll up conditionally. Always document the valid aggregation path in your schema comments.
- **Forgetting the grain:** If your fact table mixes different time granularities (some rows daily, some monthly), aggregation becomes ambiguous. Enforce one grain per table; use separate tables or views for different grains.
- **Timestamp vs. date in the PK:** Use DATE for balance snapshots, TIMESTAMP when intraday precision matters. The grain choice shapes which dimensions can be safely grouped.
- **Related to slowly changing dimensions (SCDs):** Semi-additive facts often pair with Type 2 SCDs (tracking history). A salary measure at a point in time links to a job_dimension version, not just job_id.
- **Worth revisiting:** Test your schemas by writing a query that *should* fail (e.g., "sum salary across all years") and confirm it either errors or returns a documented warning.
