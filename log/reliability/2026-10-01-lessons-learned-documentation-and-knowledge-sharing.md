---
date: 2026-10-01
phase: reliability
topic: Lessons learned: documentation and knowledge sharing
---

# Lessons learned: documentation and knowledge sharing

*Quality, reliability and the professional layer*

## Concept

Documentation and knowledge sharing are the bridge between building something that works and building something that can be maintained, debugged, and evolved by others—or by yourself six months later. Without it, you're the only person who understands why certain transformations exist, why a particular join logic was chosen, or what happens when a data quality check fails. This creates a single point of failure and a bottleneck: the system becomes fragile because fixes depend on one person's memory.

In data engineering specifically, documentation matters when pipelines touch production data, when downstream consumers depend on outputs, or when failure modes aren't obvious. A SQL transformation that seems intuitive to you becomes cryptic to someone reading it under pressure at 3 AM during an incident. Poor documentation also makes it impossible to onboard teammates, causes repeated mistakes (the same bug fixed twice), and erodes trust in data quality.

What breaks without it: incident response becomes slower; data consumers lose confidence in schema changes; technical debt accumulates silently because no one remembers why a workaround exists; and you can't safely refactor without fear of breaking something you forgot about.

## Practice

**Problem:** Your job_postings_fact table has a column `job_posted_date` that sometimes contains future dates due to a timezone conversion issue in the upstream source. A filter removes these, but it's buried in a 200-line transformation and has no comment explaining why.

**Solution:**

```sql
-- Filter out future-dated postings caused by upstream timezone misalignment (JIRA-1847)
-- Source system uses server local time; we normalize to UTC but some records still arrive
-- with post_date > current_date. These are data quality issues, not legitimate records.
-- Impact: ~0.5% of raw records filtered; monitored via dbt test in dbt_project.yml
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM {{ ref('job_postings_raw') }}
WHERE job_posted_date <= CURRENT_DATE()
  -- TODO(team): Remove this filter once upstream team migrates to UTC timestamps (ETA Q2)
  AND job_posted_date >= '2023-01-01'  -- Earliest valid historical data
;
```

Document the *why* (timezone issue, JIRA ticket), the *impact* (0.5% rows), the *owner* (who knows the context), and the *expiration* (when this workaround should be removed).

## Notes

- **Comment debt is real:** A comment that's wrong is worse than no comment. Link to tickets, include impact numbers, and mark TODOs with owners and dates so they actually get addressed.
- **README files matter:** A pipeline isn't complete without a markdown file describing inputs, outputs, freshness SLA, known limitations, and who to contact. This is the difference between "I built this" and "I own this."
- **Schema documentation is underrated:** Add descriptions to every column in your dbt yml, data catalog, or schema comments. Future you will not remember why `salary_year_avg` excludes contractor roles.
- **Connect to observability:** Good documentation includes runbooks: what do I do when X check fails? What does a normal alert look like? This bridges documentation and reliability.
- **This is part of code review:** Documentation quality should be reviewed as rigorously as logic. A PR that changes a join condition without updating its explanation shouldn't merge.
