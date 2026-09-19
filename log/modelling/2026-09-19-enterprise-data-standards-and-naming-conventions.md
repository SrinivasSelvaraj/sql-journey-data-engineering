---
date: 2026-09-19
phase: modelling
topic: Enterprise data standards and naming conventions
---

# Enterprise data standards and naming conventions

*Data modelling and warehousing*

## Concept

Enterprise data standards are agreed-upon rules for naming, typing, and structuring data so anyone on your team can understand a dataset without asking you. This includes conventions like prefixing columns by entity (`job_`, `user_`), using consistent tense (past for events, present for attributes), and choosing semantic names over abbreviations (`salary_year_avg` not `sal_yr`).

Without standards, you create friction: analysts waste time guessing what `sal` means, code reviews become arguments about naming, and migrations become nightmares because no one knows if `date_created` and `posted_date` are the same thing. In a warehouse shared across teams, this friction scales linearly with headcount.

Good standards become invisible—they're the opposite of clever. The goal is predictability: if I see a column starting with `job_`, I expect it to describe a job; if it ends in `_date`, I expect a DATE type; if it's a boolean, I expect it to answer a yes/no question clearly.

## Practice

**Problem:** A junior analyst queries the schema and writes:
```sql
SELECT job_title_short, job_posted_date 
FROM job_postings_fact 
WHERE job_work_from_home = TRUE;
```
They get results but don't know: Is `job_posted_date` when it was first posted or when it expires? Is `job_work_from_home` a legacy flag (only TRUE if fully remote) or does it include hybrid? The column names lie through ambiguity.

**Solution:** Rename with clarity and add a comment layer:
```sql
-- In schema definition
CREATE TABLE job_postings_fact (
    job_id INT,
    job_title_short VARCHAR(100),  -- COMMENT: Shortened job title, max 100 chars
    salary_year_avg DECIMAL(10,2),
    is_remote BOOLEAN,  -- COMMENT: TRUE if remote-eligible, includes hybrid
    posted_date DATE,   -- COMMENT: Date job first appeared in source
    expires_date DATE,  -- COMMENT: Date posting was removed or marked closed
    job_location VARCHAR(255)
);

-- Now the query is unambiguous:
SELECT job_title_short, posted_date 
FROM job_postings_fact 
WHERE is_remote = TRUE;
```

## Notes

- **Boolean naming:** Prefix with `is_` or `has_` (not `job_work_from_home`—that's a noun phrase). This forces your brain into yes/no mode and prevents confusion in WHERE clauses.

- **Date granularity matters:** `posted_date` vs. `posted_timestamp`—if you only have the date, say so. Downstream users shouldn't guess whether 3 AM events exist.

- **Metric vs. dimension:** Fact tables mix metrics (salary_year_avg) and dimensions (job_title_short). Consider separating into dimensions early; it clarifies intent and reduces update chaos.

- **Versioning and drift:** Standards get abandoned when pressure hits. Document why each rule exists (e.g., "We use `_date` not `_dt` because tools auto-detect DATE type from suffix"). This survives team turnover.

- **Adjacent: Data dictionaries and lineage.** Standards are useless if not documented. Link them to a live data dictionary (dbt docs, Collibra) so naming rules stay in sync with queries. Also connects to lineage—good naming makes column-level lineage readable.
