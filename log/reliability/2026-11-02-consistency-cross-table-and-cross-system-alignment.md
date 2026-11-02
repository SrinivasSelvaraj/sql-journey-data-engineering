---
date: 2026-11-02
phase: reliability
topic: Consistency: cross-table and cross-system alignment
---

# Consistency: cross-table and cross-system alignment

*Quality, reliability and the professional layer*

## Concept

Consistency is the guarantee that related data across tables and systems tells the same story. When you query a job posting's salary in `job_postings_fact`, join it to a skills table, and cross-check against your warehouse metadata—all three should agree on what "truth" is for that record. Without this alignment, you build pipelines that technically run but produce unreliable outputs: a salary marked as $120k in one table and $125k in another, a job location that contradicts the geolocation dimension, or a posting date that doesn't match upstream sources.

Consistency breaks when definitions drift between layers (raw, transformed, mart), when updates in one system don't propagate to dependent tables, when timestamps are interpreted differently, or when you lack a single source of truth. The professional difference is recognizing that a pipeline running successfully ≠ a pipeline producing trustworthy data. Someone trusted to own data infrastructure proactively defines and enforces consistency rules—often through constraints, reconciliation tests, and versioned schemas—rather than discovering inconsistencies after stakeholders have already made decisions on bad data.

## Practice

**Problem:** You load job postings from two upstream sources into the same `job_postings_fact` table. Source A uses `YYYY-MM-DD HH:MM:SS UTC`, while Source B uses Unix timestamps. Both populate `job_posted_date` but sometimes disagree by hours due to timezone mishandling. A dashboard using `job_posted_date` to trend postings by week produces incorrect counts.

```sql
-- Add a consistency check and reconciliation
SELECT 
  job_id,
  source_system,
  job_posted_date,
  job_posted_date_raw,
  CASE 
    WHEN source_system = 'source_a' 
      THEN CAST(job_posted_date_raw AS TIMESTAMP)
    WHEN source_system = 'source_b' 
      THEN TO_TIMESTAMP(job_posted_date_raw / 1000)
  END AS job_posted_date_normalized,
  ABS(EXTRACT(EPOCH FROM (
    job_posted_date - 
    CASE 
      WHEN source_system = 'source_a' THEN CAST(job_posted_date_raw AS TIMESTAMP)
      WHEN source_system = 'source_b' THEN TO_TIMESTAMP(job_posted_date_raw / 1000)
    END
  ))) AS seconds_discrepancy
FROM job_postings_fact
WHERE seconds_discrepancy > 60  -- Flag records that differ by >1 minute
ORDER BY seconds_discrepancy DESC;
```

Then: standardize on UTC in the transform layer, document the canonical definition, and add a test asserting `COUNT(DISTINCT job_id) = COUNT(*)` (no duplicate definitions of the same job).

## Notes

- **Schema versioning matters**: consistency isn't enforced if downstream teams don't know which version of the schema to trust. Use metadata or explicit `data_version` columns.
- **Reconciliation is a recurring task, not a one-time fix**: set up periodic comparisons between source and warehouse, and between tables that should logically match (e.g., unique job IDs in postings vs. in applications).
- **Timestamp handling is a common culprit**: always store in UTC, document timezone interpretation rules in lineage, and test time-based joins explicitly.
- **Connects to:** data contracts (formalizing what consistency looks like), observability (detecting drift), and governance (who owns fixing inconsistencies).
- **Revisit when**: onboarding a new source, adding a mart layer, or seeing unexplained variances in business metrics.
