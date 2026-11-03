---
date: 2026-11-03
phase: reliability
topic: Golden record: single source of truth for entities
---

# Golden record: single source of truth for entities

*Quality, reliability and the professional layer*

## Concept

A golden record is the single, authoritative version of an entity—a customer, product, job posting, or account—that all downstream systems and reports reference. Without it, you end up with inconsistent versions scattered across pipelines: one system says a customer has 3 addresses, another says 5; one report shows a job salary at $85k, another at $92k. The golden record eliminates this by establishing one source of truth before data branches into analytics, reporting, and operational systems.

This matters most when multiple source systems feed the same domain (CRM, billing, support all have customer data), or when the same entity is transformed multiple times. It's the difference between a pipeline that works and a platform that *can be trusted*. Without it, stakeholders lose confidence in numbers, data quality issues hide in plain sight, and debugging becomes archaeology.

The cost of not having one is operational: people create workarounds, maintain shadow spreadsheets, and argue about which number to trust. Data ownership becomes unclear. You become the person who has to answer "which version is correct?" every time someone finds a discrepancy.

## Practice

**Problem:** Your job_postings_fact table is loaded from three sources: LinkedIn, Indeed, and your company's internal board. The same job posting sometimes appears in multiple sources with different salaries (due to rounding, currency conversion, or stale data). Reports now show conflicting numbers, and stakeholders don't know which salary to trust for budget planning.

```sql
-- Golden record: single job posting with lineage and quality flags
CREATE TABLE job_postings_golden (
    job_id STRING PRIMARY KEY,
    job_title_short STRING,
    salary_year_avg DECIMAL(10,2),
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location STRING,
    source_system STRING,  -- which system is authoritative
    salary_confidence_score FLOAT,  -- data quality signal
    last_updated TIMESTAMP,
    is_current BOOLEAN
);

-- Load with explicit precedence: internal > LinkedIn > Indeed
INSERT INTO job_postings_golden
SELECT 
    COALESCE(internal.job_id, linkedin.job_id, indeed.job_id) AS job_id,
    COALESCE(internal.title, linkedin.title, indeed.title) AS job_title_short,
    COALESCE(internal.salary, linkedin.salary, indeed.salary) AS salary_year_avg,
    COALESCE(internal.remote, linkedin.remote, indeed.remote) AS job_work_from_home,
    COALESCE(internal.posted_date, linkedin.posted_date, indeed.posted_date) AS job_posted_date,
    COALESCE(internal.location, linkedin.location, indeed.location) AS job_location,
    CASE 
        WHEN internal.job_id IS NOT NULL THEN 'internal'
        WHEN linkedin.job_id IS NOT NULL THEN 'linkedin'
        ELSE 'indeed'
    END AS source_system,
    CASE 
        WHEN internal.job_id IS NOT NULL THEN 0.95
        WHEN linkedin.job_id IS NOT NULL THEN 0.80
        ELSE 0.70
    END AS salary_confidence_score,
    CURRENT_TIMESTAMP AS last_updated,
    TRUE AS is_current
FROM internal_jobs internal
FULL OUTER JOIN linkedin_jobs linkedin 
    ON internal.job_id = linkedin.job_id
FULL OUTER JOIN indeed_jobs indeed 
    ON internal.job_id = indeed.job_id;
```

## Notes

- **Precedence rules must be documented and enforced:** Hard-code source priority in your logic, not in analyst intuition. A comment explaining *why* internal data ranks highest (fresher, verified by humans) prevents future rewrites.
- **Lineage and confidence matter as much as values:** Track which source won for each record and add quality signals (confidence scores, match flags). This lets downstream consumers know when to trust a number vs. flag it for review.
- **Deduplication and matching is hard:** Joining across sources requires robust entity matching (fuzzy match on job title + location, handle typos). A weak match logic becomes a golden record liability; invest here early.
- **This connects to:** data contracts (who owns the golden record's SLA?), slowly changing dimensions (job salary changes—track history), and data observability (alert when sources disagree by >10%).
- **Revisit when:** adding a new source system, or when downstream reports show divergence. These are signals your golden record logic is outdated.
