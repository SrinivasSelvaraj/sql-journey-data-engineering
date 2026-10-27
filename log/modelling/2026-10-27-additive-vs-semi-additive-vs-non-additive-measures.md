---
date: 2026-10-27
phase: modelling
topic: Additive vs semi-additive vs non-additive measures
---

# Additive vs semi-additive vs non-additive measures

*Data modelling and warehousing*

## Concept

Measure classification determines how facts behave when aggregated across dimensions—critical for preventing nonsensical queries that look syntactically correct but answer the wrong question. **Additive measures** (like revenue, clicks, or headcount) sum meaningfully across all dimensions; **semi-additive measures** (like account balance, inventory quantity, or temperature) sum across some dimensions but not others (never across time without a specific rule); **non-additive measures** (like price per unit, margin percentage, or exchange rates) don't sum at all and require a denominator or weighted calculation.

Without explicit classification, analysts create false aggregations—summing a price across all job postings gives a meaningless number, yet a query tool won't stop them. Documentation and fact table design prevent this by signaling intent: additive facts live as-is, semi-additive facts need grain specification and SUM restrictions, non-additive facts belong in a separate dimension or require derived columns (SUM of numerator / SUM of denominator).

The schema's grain (the lowest level of detail) determines measure behavior. A fact table at job-posting grain has different additive properties than one at company-month grain.

## Practice

**Problem:** You've built `job_postings_fact` with `salary_year_avg` and `job_work_from_home`. An analyst runs:
```sql
SELECT job_location, SUM(salary_year_avg) 
FROM job_postings_fact 
GROUP BY job_location;
```
This sum is meaningless—it's not total payroll, not total money, just concatenated salary figures. How do you model this correctly?

**Solution:** Classify and document; add a `measure_type` column or metadata layer:

```sql
-- In your fact table definition or documentation:
-- salary_year_avg: NON-ADDITIVE (use AVG or weighted calc, never SUM)
-- job_count: ADDITIVE (safe to SUM across any dimension)
-- remote_count: ADDITIVE (count of remote jobs)

-- Correct query for analyst:
SELECT 
  job_location,
  COUNT(DISTINCT job_id) AS job_count,
  AVG(salary_year_avg) AS avg_salary,
  SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) AS remote_jobs
FROM job_postings_fact
GROUP BY job_location;
```

Add a `job_count` additive measure (or compute from row count) to the fact table. Document `salary_year_avg` as non-additive in your metadata/wiki; consider a derived table if analysts frequently need aggregated salary data.

## Notes

- **Non-additive confusion:** Price, rate, ratio, and percentage columns are non-additive; SUM(price × quantity) requires storing both components separately or pre-computing revenue as additive.
- **Semi-additive danger:** Account balance at month-end sums across accounts (additive) but not across months without picking a snapshot date (semi-additive). Clarify the grain in table or column names: `account_balance_month_end_fact` signals don't aggregate across time naively.
- **Grain is everything:** The same column (`employee_count`) is additive at company-month grain but semi-additive at company-day grain. Always document fact table grain explicitly.
- **Connects to:** dimensional modeling (Kimball), slowly changing dimensions (how do measures change with SCD Type 2?), and data contracts—a schema that forces the right aggregation is a contract with your consumers.
- **Revisit:** Conformed dimensions and facts across schemas; how semi-additive measures behave in slowly changing scenarios; query guardrails (views, materialized aggregates) that enforce measure rules at the database layer.
