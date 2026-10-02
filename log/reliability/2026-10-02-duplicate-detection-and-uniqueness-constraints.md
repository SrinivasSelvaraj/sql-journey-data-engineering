---
date: 2026-10-02
phase: reliability
topic: Duplicate detection and uniqueness constraints
---

# Duplicate detection and uniqueness constraints

*Quality, reliability and the professional layer*

## Concept

Duplicate detection and uniqueness constraints are the mechanisms that prevent the same logical entity from appearing multiple times in your data warehouse. A duplicate isn't just a row that looks identical—it's a violation of the contract you've made with stakeholders about what each record represents. Without explicit detection and constraints, you silently corrupt aggregations (job counts inflate, salary averages shift), break join logic, and erode confidence in the system.

Uniqueness constraints come in two forms: natural keys (combinations of business columns that should be unique) and surrogate keys (system-generated identifiers). The difference matters. A natural key like (job_id, job_posted_date) tells you what uniqueness *means* in the domain. A surrogate key like job_posting_sk tells you it's been deduplicated, but hides the actual rule. The professional layer requires both: you detect duplicates using natural key logic, then enforce it through constraints or idempotent load patterns.

This becomes critical in incremental pipelines. If you run a job twice, do posting counts double? If a source system retransmits records, does your fact table expand? The answer should always be "no"—controlled by an explicit strategy, not luck.

## Practice

**Problem:** Your source system sometimes sends duplicate job postings (same job_id, posted on the same date, from API retries or batch reprocessing). A naive incremental load creates duplicates in job_postings_fact. You need to detect and eliminate them before the fact table receives them.

```sql
-- Detect duplicates using natural key (job_id, job_posted_date)
WITH duplicates AS (
  SELECT 
    job_id,
    job_posted_date,
    COUNT(*) as occurrence_count
  FROM job_postings_fact
  GROUP BY job_id, job_posted_date
  HAVING COUNT(*) > 1
)
-- Remove duplicates: keep only the first occurrence (arbitrary but deterministic)
DELETE FROM job_postings_fact
WHERE ROW_NUMBER() OVER (PARTITION BY job_id, job_posted_date ORDER BY job_posting_sk) > 1;

-- Add a unique constraint to prevent future duplicates
ALTER TABLE job_postings_fact
ADD CONSTRAINT uk_job_postings_natural_key UNIQUE (job_id, job_posted_date);
```

## Notes

- **Confusing uniqueness with distinctness:** DISTINCT removes row-level duplicates; uniqueness constraints prevent duplicates from entering at all. The former is a band-aid; the latter is architecture.
- **Surrogate keys don't guarantee uniqueness:** A job_posting_sk of 1001, 1002, 1003 can still represent two copies of the same job. Always define and validate the natural key separately.
- **Incremental loads need idempotency:** Instead of constraints alone, use merge/upsert logic (MERGE INTO or INSERT ... ON CONFLICT) to make your pipeline safe to re-run. Constraints catch mistakes; idempotency prevents them.
- **Adjacent topics:** This connects directly to slowly changing dimensions (SCD Type 1/2 require duplicate handling), data lineage (knowing *which* occurrence is the "real" one), and testing (duplicate detection rules must be tested as rigorously as transformations).
- **Revisit when:** Adding a new source, changing grain (moving from daily to hourly), or when you hear "counts don't match the source system"—that's usually a duplicate problem wearing a different mask.
