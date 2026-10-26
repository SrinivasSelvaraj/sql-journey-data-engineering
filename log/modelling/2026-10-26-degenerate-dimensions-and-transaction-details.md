---
date: 2026-10-26
phase: modelling
topic: Degenerate dimensions and transaction details
---

# Degenerate dimensions and transaction details

*Data modelling and warehousing*

## Concept

A **degenerate dimension** is a column in a fact table that acts like a dimension (describes *what* happened) but has no separate dimension table. Examples include transaction IDs, order numbers, short codes, or flags. They're essential for transaction-level detail because they let you group and filter at the grain of the fact without forcing a join to another table.

Transaction details—like individual order line items, clicks, or job applications—live at a fine grain where a separate dimension would be overkill or would break the natural key. A degenerate dimension keeps those descriptors close to the event, making queries fast and schemas readable. Without them, you either bloat your fact table with redundant lookups or lose context entirely.

The distinction matters most when someone queries your fact table and needs to filter or group by something that's specific to that transaction but not shared across many facts. If `job_title_short` is always paired with a `job_id` and rarely changes, it belongs in the fact table as a degenerate dimension—not as a foreign key to a separate dim_job_title.

## Practice

**Problem:** You need to let analysts find all remote jobs posted in the last 30 days, grouped by location, and see the average salary. Today's approach forces them to join multiple tables or ask you what each column means.

```sql
-- Using degenerate dimensions in the fact table
SELECT 
  job_location,
  COUNT(DISTINCT job_id) AS job_count,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary,
  SUM(CASE WHEN job_work_from_home THEN 1 ELSE 0 END) AS remote_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY job_location
ORDER BY avg_salary DESC;
```

Here `job_title_short`, `job_work_from_home`, and `job_posted_date` are degenerate dimensions. They're stored in the fact table itself, so no join is needed. Column names are self-documenting (e.g., `job_work_from_home BOOLEAN` is clearer than a code like `remote_flag_id`).

## Notes

- **Over-normalization trap:** Resist the urge to create a dim_work_location or dim_job_title_short if the value is unique per transaction or changes rarely. A fact table bloated with foreign keys is harder to query than one with denormalized text.
- **Grain consistency:** Degenerate dimensions must match the grain of your fact table. If `job_postings_fact` is one row per job posting, then `job_title_short` is valid; if it's one row per application, add `applicant_id` as a degenerate dimension too.
- **Self-documenting schema:** Use clear naming (e.g., `job_posted_date`, not `posted_dt` or `p_date`) so analysts can write queries without a data dictionary.
- **Adjacent concept—conformed dimensions:** Some attributes should still live in a shared dimension (e.g., a `dim_company` if many job postings share the same employer). Degenerate dimensions are for *transaction-specific* details.
- **Revisit:** Compare this to Kimball's slowly changing dimensions (SCD) and bridge tables when a single job posting might have multiple titles or locations over time.
