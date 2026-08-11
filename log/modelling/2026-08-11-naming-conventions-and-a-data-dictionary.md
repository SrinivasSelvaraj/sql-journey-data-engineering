---
date: 2026-08-11
phase: modelling
topic: Naming conventions and a data dictionary
---

# Naming conventions and a data dictionary

*Data modelling and warehousing*

## Concept

A naming convention is a systematic ruleset for how you name tables, columns, and other schema objects. A data dictionary documents what each object means, its type, acceptable values, and business context. Together, they let analysts and engineers query your warehouse without interrupting you to ask "does `salary_year_avg` include bonuses?" or whether `job_work_from_home` means fully remote or hybrid.

Without clear naming, teams waste time reverse-engineering logic. Someone might assume `job_posted_date` is the date the job was filled rather than published, leading to incorrect reporting. Ambiguous column names like `status` or `flag` force repeated Slack messages. A data dictionary becomes your contract: it defines truth once, preventing duplicate work and conflicting interpretations across teams.

This matters most when ownership becomes distributed. Early projects survive on tribal knowledge, but scaling requires documentation. The cost is small upfront (15 minutes per table) and pays back in reduced onboarding time, fewer bugs in downstream dashboards, and faster incident investigation.

## Practice

**Problem:** A junior analyst queried the `job_postings_fact` table and assumed `salary_year_avg` was the salary *range midpoint* for comparability. They built a compensation report that was published before anyone caught that the column actually contains the mean of all posted salaries for that job title across all locations—a different metric entirely. The report misled stakeholders.

**Solution:** Establish naming rules and a documented data dictionary:

```sql
-- Apply consistent naming convention:
-- fact tables: [domain]_fact
-- dimensions: [domain]_dim
-- boolean flags: is_[condition] or has_[property]
-- dates: [action]_date
-- amounts: [measure]_[unit]

-- Then document in a data dictionary (stored as a comment, wiki, or metadata table):

COMMENT ON TABLE job_postings_fact IS 
'Fact table: one row per unique job posting. Updated daily.';

COMMENT ON COLUMN job_postings_fact.salary_year_avg IS 
'Annual salary in USD. Mean of all salaries posted for this job_title_short 
across all locations in the source data. NULL if not disclosed. Does NOT include 
bonuses, equity, or benefits. Calculated at ETL load time. See dim_salary_ranges for percentile bands.';

COMMENT ON COLUMN job_postings_fact.job_work_from_home IS 
'Boolean: TRUE if posting explicitly allows remote work (any % remote). 
FALSE if on-site or hybrid only. NULL if not specified. Does not indicate 
% of remote allowed—see job_postings_dim.remote_work_policy for details.';

-- Query with confidence:
SELECT job_title_short, AVG(salary_year_avg) as avg_compensation
FROM job_postings_fact
WHERE job_work_from_home = TRUE
GROUP BY job_title_short;
```

## Notes

- **Naming pitfall:** Mixing tenses (`posted_date` vs `posting_date`) or units without suffixes (`salary` vs `salary_usd`). Pick one pattern and enforce it across all schemas.
- **Boolean trap:** Avoid names like `active`, `valid`, or `remote` without a prefix—they're ambiguous. Use `is_active`, `is_valid`, `is_remote_eligible` instead.
- **Data dictionary as code:** Store comments in your schema DDL, not external documents. External wikis drift; schema comments travel with migrations and are visible in tools like `DESCRIBE TABLE`.
- **Related:** This connects to data lineage (tracking where each column originates) and data quality rules (documenting which values are valid). A dictionary should reference both.
- **Revisit:** As domains shift or columns are deprecated, keep the dictionary current. Mark obsolete columns with a comment but don't delete them—analysts rely on historical queries.
