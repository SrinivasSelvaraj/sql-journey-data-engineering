---
date: 2026-08-31
phase: modelling
topic: NULL as unknown vs NULL as not applicable distinction
---

# NULL as unknown vs NULL as not applicable distinction

*Data modelling and warehousing*

## Concept

NULL can represent two fundamentally different states: **unknown** (we don't know the value) and **not applicable** (the column doesn't apply to this row). Without distinguishing them, downstream analysts can't interpret results correctly. Unknown suggests "find this data," while not applicable suggests "this column is irrelevant here."

In a job posting schema, this distinction directly affects query logic and business metrics. If `salary_year_avg` is NULL because the employer hasn't disclosed it (unknown), filtering those rows out underestimates average salary. If NULL means "this role has no salary" (not applicable—perhaps it's commission-only or volunteer), that's a different decision. The schema must make this intention explicit, otherwise every analyst queries the data differently.

Without clarity, you get silent data quality issues: aggregates that exclude uncertain values, joins that lose rows unexpectedly, and reporting that changes depending on who interprets the NULL. The cost is compounded when your team grows—everyone invents their own assumptions.

## Practice

**Problem:** You have job postings where some remote roles have no location specified, some roles are contract-to-hire with unknown salary, and some volunteer roles genuinely have no salary field. All three are NULL in `job_location` and `salary_year_avg`. When you report "average salary across all jobs," the meaning becomes ambiguous—are you excluding unknowns or not applicables?

```sql
-- Solution: Split nullable columns or add explicit reason codes

-- Option 1: Create separate columns for unknowns
ALTER TABLE job_postings_fact ADD COLUMN salary_year_avg_known BOOLEAN;
ALTER TABLE job_postings_fact ADD COLUMN job_location_type VARCHAR(20); 
-- 'remote', 'hybrid', 'onsite', 'unknown'

-- Now queries are explicit:
SELECT 
  AVG(salary_year_avg) as avg_salary_known,
  COUNT(CASE WHEN salary_year_avg_known = FALSE THEN 1 END) as count_undisclosed
FROM job_postings_fact
WHERE salary_year_avg_known = TRUE;

-- Option 2: Use sentinel values instead of NULL
UPDATE job_postings_fact 
SET salary_year_avg = -1 
WHERE job_type = 'volunteer' AND salary_year_avg IS NULL;

UPDATE job_postings_fact 
SET job_location = 'REMOTE_UNDISCLOSED' 
WHERE job_work_from_home = TRUE AND job_location IS NULL;

-- Now NULL explicitly means "unknown/needs investigation"
SELECT * FROM job_postings_fact WHERE salary_year_avg IS NULL; 
-- Returns only truly unknown cases, not policy-driven absences
```

## Notes

- **Mistake:** Treating NULL as a homogeneous category; forces downstream logic to guess context every time the column is used.
- **Adjacent topic:** Surrogate keys and type-2 slowly changing dimensions often require this distinction—when a dimension attribute becomes not applicable, NULL signals structural change rather than data arrival delay.
- **Adjacent topic:** Data lineage and provenance; unknown NULLs should trigger different alerting/SLA logic than not-applicable NULLs.
- **Revisit:** Test this distinction in your fact/dimension star schema; NULL handling often reveals missing conformed dimensions (e.g., a "Salary Disclosure" dimension with attributes like "undisclosed," "estimated," "posted").
- **Practical rule:** If you can't explain to a non-technical stakeholder why a NULL exists, your schema needs a reason column or a constraint clarification.
