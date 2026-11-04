---
date: 2026-11-04
phase: reliability
topic: Data pipelines as code: version control and code review
---

# Data pipelines as code: version control and code review

*Quality, reliability and the professional layer*

## Concept

Data pipelines as code means treating your pipeline logic—SQL transforms, orchestration DAGs, data quality checks—as versioned software artifacts, not ad-hoc scripts. Every change is tracked, reviewed, and reproducible. This matters because pipelines are production systems: they feed analytics, trigger decisions, and populate dashboards. Without version control, you lose the ability to answer "who changed what and why?" When a metric suddenly breaks, you can't blame a query tweak from three weeks ago if it lives only in a database or a shared drive.

Code review enforces accountability. A second set of eyes catches logic errors (off-by-one date filters, unintended aggregations) before they corrupt downstream data. It also distributes knowledge—junior engineers learn by reviewing senior code; seniors stay aware of what's being built. Without this gate, ownership becomes unclear: if a pipeline fails at 2 AM, who is responsible for fixing it? The person who wrote it six months ago and never documented it? The person who modified it last week without understanding the context?

Trust means being the person others call when things break. That requires transparency (code in Git), communication (clear commit messages and PR descriptions), and rigor (automated tests, linting, documented assumptions).

## Practice

**Problem:** Your `job_postings_fact` table is updated daily. A colleague adds a filter to exclude remote positions without documenting why. Two weeks later, the VP of Remote Hiring notices remote job counts dropped 80% overnight. You have no Git history, no PR discussion, and no way to know if this was intentional.

**Solution:**

```sql
-- transforms/job_postings_fact.sql
-- Versioned in Git, reviewed before merge

WITH raw_postings AS (
  SELECT 
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location
  FROM {{ source('raw', 'job_postings') }}
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL '1 year'
    -- Excludes remote positions intentionally (PR #347)
    -- See discussion: remote roles handled separately in job_postings_remote_fact
    AND job_work_from_home = FALSE
)

SELECT * FROM raw_postings
```

With this in Git (and a required code review), the VP can:
1. Check the Git blame and see the commit + PR link
2. Read the discussion thread explaining the split
3. Propose a revert or clarification via a new PR with visibility

## Notes

- **Commit messages matter.** "fixed query" tells you nothing. "Exclude remote roles per product decision (PR #347, tracking issue #891)" lets you find context in 10 seconds, not 10 minutes.
- **Automation prevents drift.** Linters catch unused columns, tests verify row counts haven't dropped unexpectedly, dbt snapshot comparisons flag unintended schema changes. Code review is human-scale; automation is scalable.
- **Documentation lives in code.** Comments in SQL and docstrings in DAGs are version-controlled and reviewed alongside logic changes. Markdown files in the repo are easier to find than Confluence pages that rot.
- **Distinguish between schema ownership and pipeline ownership.** One person owns the `job_postings_fact` table definition and breaking changes; a team owns the pipeline that populates it. Clear CODEOWNERS files (in Git) define this.
- **Link commits to tickets.** "Closes #891" in a PR description auto-links your code change to the business context (a feature request, a bug report, a data quality incident), creating a chain of causality.
