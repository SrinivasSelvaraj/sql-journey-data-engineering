---
date: 2026-09-10
phase: reliability
topic: Dimension conformance: referential integrity validation
---

# Dimension conformance: referential integrity validation

*Quality, reliability and the professional layer*

## Concept

Dimension conformance validates that every foreign key reference in a fact table points to an actual, valid record in its corresponding dimension table. Without this check, your analytics layer becomes unreliable: dashboards show jobs linked to non-existent locations, salary metrics aggregate against deleted employee records, or orphaned facts pollute your aggregations. This is referential integrity validation—the structural contract that keeps distributed data honest.

The vulnerability grows with scale. A slowly changing dimension that soft-deletes records, a late-arriving dimension, or a race condition in parallel loads can all break the chain silently. You might not notice for weeks if your fact table's job_location_id references a location_dim row that was marked inactive or never loaded at all. This is why conformance validation must run *after* both tables load but *before* dependent models consume them—it's a gate, not a footnote.

When you own the pipeline, you own the contract. This means logging mismatches, deciding whether to quarantine failing records, retry the dimension load, or alert stakeholders. It separates amateur pipelines (which hope conformance is true) from professional ones (which verify and document it).

## Practice

**Problem:** Your `job_postings_fact` table includes a `job_location` text field, but downstream analytics need to join to a `locations_dim` table via `location_id`. After a dimension reload, some facts reference location IDs that no longer exist—either they were deleted or the dimension load failed partway through.

```sql
-- Conformance validation: find orphaned facts
SELECT 
  COUNT(*) as orphaned_count,
  COUNT(DISTINCT job_id) as affected_jobs
FROM job_postings_fact jpf
LEFT JOIN locations_dim ld 
  ON jpf.job_location_id = ld.location_id
WHERE ld.location_id IS NULL
  AND jpf.job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY;

-- Quarantine pattern: mark or isolate non-conforming records
INSERT INTO job_postings_fact_quarantine
SELECT jpf.* 
FROM job_postings_fact jpf
LEFT JOIN locations_dim ld 
  ON jpf.job_location_id = ld.location_id
WHERE ld.location_id IS NULL
  AND jpf.load_timestamp = (SELECT MAX(load_timestamp) FROM job_postings_fact);

-- Delete quarantined records from fact table
DELETE FROM job_postings_fact 
WHERE job_id IN (SELECT job_id FROM job_postings_fact_quarantine);
```

## Notes

- **Silent failures are the worst:** A NULL join in downstream queries masks conformance issues. Explicit validation with alerts is mandatory—don't rely on data consumers to spot the problem.
- **Timing matters:** Validate *after* dimension loads complete but *before* fact consumption. In layered architectures, this lives in your reliability/quality layer, separate from transformation logic.
- **Soft deletes complicate this:** If your dimension uses `is_active` flags, conformance rules must account for temporal validity. A "deleted" location is still a valid reference for historical jobs—context matters.
- **Connects to:** slowly changing dimensions (SCD Type 2), late-arriving facts, data lineage tracking, and observability. Also overlaps with data contracts and schema validation.
- **Revisit:** the difference between validation (does this fail?) and remediation (what do we do about it?). Professional pipelines separate detection from response, allowing human judgment.
