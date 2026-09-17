---
date: 2026-09-17
phase: modelling
topic: Mart-specific aggregation tables and redundancy
---

# Mart-specific aggregation tables and redundancy

*Data modelling and warehousing*

## Concept

Mart-specific aggregation tables are pre-computed, denormalized tables built for a particular business function or analytics team. Instead of querying raw facts and dimensions repeatedly, a data analyst working on recruitment metrics queries a single, purpose-built table with job titles already standardized, salary bands pre-bucketed, and remote-work flags already labeled. This trades storage and ETL complexity for query speed and semantic clarity.

Redundancy is intentional here. You *want* the same metric calculated the same way in every table that uses it, even if that means storing it twice. Without this, one team's "remote job" definition drifts from another's, reports contradict each other, and stakeholders lose trust. A well-designed mart eliminates the need to ask "which salary bucket does 95k fall into?" — the answer is baked in.

This matters most when teams have different query patterns or SLAs. A finance team may need monthly salary aggregates by region; a recruiter needs daily counts by job level. A single normalized schema forces both to write complex joins and case statements. Separate marts let each team query like the data was built for them.

## Practice

**Problem:** Your recruitment team needs a daily report showing job openings by seniority level and remote status. They're currently joining `job_postings_fact` with a manually-maintained spreadsheet to assign seniority levels, and their SQL has become a mess of case statements to bucket salaries. Build a recruitment mart so they can select and group by clean column names.

```sql
-- Source: job_postings_fact
-- Create a recruitment-specific mart
CREATE TABLE recruitment_mart AS
SELECT
  job_id,
  job_posted_date,
  job_title_short,
  CASE
    WHEN salary_year_avg < 60000 THEN 'Junior'
    WHEN salary_year_avg BETWEEN 60000 AND 100000 THEN 'Mid'
    WHEN salary_year_avg > 100000 THEN 'Senior'
    ELSE 'Unknown'
  END AS seniority_level,
  CASE
    WHEN job_work_from_home = TRUE THEN 'Remote'
    ELSE 'On-site'
  END AS work_arrangement,
  job_location,
  salary_year_avg
FROM job_postings_fact;

-- Now recruiters query this:
SELECT
  job_posted_date,
  seniority_level,
  work_arrangement,
  COUNT(*) as job_count,
  ROUND(AVG(salary_year_avg), 0) as avg_salary
FROM recruitment_mart
GROUP BY job_posted_date, seniority_level, work_arrangement
ORDER BY job_posted_date DESC, job_count DESC;
```

## Notes

- **Sync or staleness?** Decide whether your mart updates daily, hourly, or on-demand. Document the lag. Stale data is better than contradictory data, but both are worse than schema clarity.
- **Naming discipline.** Use suffixes like `_mart` or `_agg` consistently. Prefix with the use case (`recruitment_mart`, `finance_mart`). This prevents confusion between source facts and derived views.
- **Avoid cascading dependencies.** Don't build a mart from another mart. Always source from facts/dimensions. Otherwise, a single upstream change breaks chains of tables and you lose auditability.
- **Version your logic.** Store the bucketing rules (salary ranges, seniority mapping) in documentation or a config table, not just buried in SQL. Future maintainers need to know why 60k is the boundary.
- **Adjacent topics:** Connects to slowly changing dimensions (how do you handle job title reclassification?), data contracts (what guarantees does this mart make to consumers?), and cost trade-offs (redundancy means higher storage; measure whether query speed gain justifies it).
