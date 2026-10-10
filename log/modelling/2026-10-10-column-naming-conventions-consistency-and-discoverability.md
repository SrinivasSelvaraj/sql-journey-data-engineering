---
date: 2026-10-10
phase: modelling
topic: Column naming conventions: consistency and discoverability
---

# Column naming conventions: consistency and discoverability

*Data modelling and warehousing*

## Concept

Column naming conventions make schemas self-documenting and queryable without tribal knowledge. A well-named column tells you its data type (via suffix), business domain (via prefix), and whether it's a dimension or metric—allowing analysts to write correct queries without asking you "is this salary monthly or annual?" or "does this boolean mean the job *allows* remote or *requires* it?"

Inconsistency creates cognitive friction: `salary_year_avg` next to `monthly_comp` next to `comp_usd` means every new analyst rebuilds mental maps of your tables. Worse, it hides bugs—a join on `user_id` and `userid` silently fails, and `is_active` vs `active_flag` suggests two different meanings when they're identical.

The payoff compounds: column naming is cheap to enforce at design time but expensive to refactor later. It's one of the few schema decisions that directly affects onboarding speed and query correctness across a team.

## Practice

**Problem:** The job_postings_fact table mixes naming styles. Some columns have business-domain prefixes (`job_` prefix), others don't. The boolean column name is ambiguous: does `job_work_from_home` mean the job *allows* remote work or *requires* it? Analysts are writing:

```sql
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_work_from_home = TRUE
```

...and getting confused results because the column actually means "eligible for remote" not "primarily remote."

**Solution:** Rename columns for consistency and clarity:

```sql
-- Refactored schema with consistent conventions:
-- Prefix: job_ for fact dimensions, salary_ for metrics
-- Suffix: _flag or _yn for booleans (explicit about true meaning)
-- Suffix: _date for temporal columns (already present)
-- Suffix: _avg or _amt for metrics

job_postings_fact(
  job_id,
  job_title_short,
  job_location,
  job_posted_date,
  salary_year_avg,
  is_remote_eligible_flag  -- explicit meaning, boolean suffix
)

-- Query intent is now unambiguous:
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE is_remote_eligible_flag = TRUE
```

## Notes

- **Boolean naming trap:** Never use `job_work_from_home` alone. Use `is_X_flag`, `X_yn`, or `X_eligible` so the true state is unambiguous. The column name should complete "is this job...?"
- **Prefix consistency matters more than the specific prefix:** Pick `job_` or `posting_` for all fact attributes and stick with it. Mixing signals that columns have different meanings.
- **Related: surrogate vs. natural keys.** Good naming conventions work hand-in-hand with clear PK/FK strategy. A column named `job_id` signals it's a reference; `job_posting_surrogate_id` signals it's synthetic.
- **Revisit: data dictionaries and schema documentation.** Naming conventions reduce but don't eliminate the need for a data catalog. They're a first line of defense, not a replacement.
- **Common mistake:** Abbreviating inconsistently (`emp_id`, `user_identifier`, `cust_no`). Pick one style and enforce it in code review.
