---
date: 2026-08-16
phase: reliability
topic: Contract testing between producers and consumers
---

# Contract testing between producers and consumers

*Quality, reliability and the professional layer*

## Concept

Contract testing is an agreement between a data producer (the pipeline or system that writes data) and its consumers (downstream jobs, dashboards, analysts) about *what* the data will look like—schema, types, nullability, value ranges, freshness SLAs. Without it, a producer can silently break contracts: rename a column, allow nulls where there weren't any, delay a daily load by 12 hours, and consumers fail in production without warning.

This matters because pipelines at scale have many consumers, often unknown to the producer. A contract surfaces these dependencies explicitly and catches breaking changes before they cascade. It's the difference between "my pipeline works" (producer perspective) and "my pipeline is *reliable for my customers*" (owner perspective). It moves quality ownership upstream.

Without contracts, you debug production failures backward: a dashboard breaks, you trace to a stale table, then discover the upstream ETL changed format last week. With contracts, you catch mismatches during deployment. It's a form of defensive programming for data systems.

## Practice

**Problem:** Your `job_postings_fact` table is consumed by three teams: a reporting dashboard expecting `job_posted_date` as DATE, an ML pipeline that treats `salary_year_avg` as required (non-null), and an analytics team querying `job_work_from_home` as BOOLEAN. A developer refactors the upstream source to nullable salary, drops the work-from-home column (it's redundant with job_location), and converts job_posted_date to TIMESTAMP for precision. Without a contract, all three consumers fail silently or crash.

**Solution:** Define and test the contract before allowing schema changes:

```sql
-- Contract: Assert the agreed schema at the start of dependent jobs
-- Run this in every consumer query/pipeline before use

WITH contract_check AS (
  SELECT
    CASE WHEN COUNT(*) = 0 THEN 'FAIL: job_postings_fact does not exist' END as check1,
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'job_postings_fact' AND column_name = 'job_work_from_home' AND data_type = 'boolean'
    ) THEN 'FAIL: job_work_from_home must be BOOLEAN' END as check2,
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'job_postings_fact' AND column_name = 'salary_year_avg' AND is_nullable = 'NO'
    ) THEN 'FAIL: salary_year_avg must be NOT NULL' END as check3,
    CASE WHEN NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_name = 'job_postings_fact' AND column_name = 'job_posted_date' AND data_type = 'date'
    ) THEN 'FAIL: job_posted_date must be DATE type' END as check4
  FROM job_postings_fact
)
SELECT * FROM contract_check WHERE check1 IS NOT NULL OR check2 IS NOT NULL OR check3 IS NOT NULL OR check4 IS NOT NULL;

-- If contract_check returns rows, the pipeline fails loudly *before* logic runs.
-- If empty, proceed with the job.
```

## Notes

- **Common mistake:** Treating contracts as optional documentation. They must be enforced as code in test suites or pre-query assertions, not wiki pages that drift.
- **Versioning matters:** When a contract must change, increment it explicitly (v1 → v2) and run both in parallel for a deprecation window so consumers migrate intentionally.
- **Adjacent topics:** Data quality frameworks (Great Expectations, dbt tests), backward-compatibility strategies, and SLA monitoring all strengthen contract discipline.
- **Freshness is part of the contract:** A schema contract is incomplete without agreeing on latency (daily by 6 AM, hourly, real-time). A schema-correct table that arrives 48 hours late is still a breach.
- **Revisit:** How contracts scale when you have 20+ consumers and a shared warehouse. This often leads to catalog/lineage tools (Collibra, Alation) that track contracts automatically.
