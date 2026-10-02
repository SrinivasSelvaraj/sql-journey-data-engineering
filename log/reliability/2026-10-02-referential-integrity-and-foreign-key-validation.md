---
date: 2026-10-02
phase: reliability
topic: Referential integrity and foreign key validation
---

# Referential integrity and foreign key validation

*Quality, reliability and the professional layer*

## Concept

Referential integrity ensures that relationships between tables remain logically consistent—a foreign key in one table must point to a valid primary key in another, or be null. Without it, you can end up with orphaned records: job applications pointing to jobs that no longer exist, salary data tied to deleted positions, or location lookups that fail silently. This becomes critical in production pipelines where data flows through multiple stages; one broken join upstream cascades into corrupted analytics downstream.

In the quality and reliability phase, referential integrity moves from "nice to have" validation to a non-negotiable checkpoint. A trusted data owner doesn't just assume relationships are sound—they enforce and monitor them. This means catching foreign key violations early (during load, not during analysis), understanding the business rules behind relationships, and knowing when a null vs. a missing reference matters differently.

Without validation, you inherit technical debt. Analysts build reports on incomplete data. Reconciliation becomes impossible. Teams lose trust in the pipeline. The cost of fixing referential integrity issues after they've spread through your warehouse is orders of magnitude higher than catching them at the gate.

## Practice

**Problem:** Your `job_postings_fact` table has a `job_location` field (text), but you want to validate that every location references a valid `locations_dimension` table (location_id, location_name, country). Currently, some records have typos or locations that don't exist in the dimension. You need to identify violations and decide how to handle them.

```sql
-- Identify referential integrity violations
SELECT 
    jpf.job_id,
    jpf.job_title_short,
    jpf.job_location,
    CASE 
        WHEN ld.location_id IS NULL THEN 'ORPHANED'
        ELSE 'VALID'
    END AS integrity_status
FROM job_postings_fact jpf
LEFT JOIN locations_dimension ld 
    ON jpf.job_location = ld.location_name
WHERE ld.location_id IS NULL
    AND jpf.job_location IS NOT NULL;

-- Add a foreign key constraint (if architecture allows)
ALTER TABLE job_postings_fact
ADD CONSTRAINT fk_job_location 
FOREIGN KEY (job_location) 
REFERENCES locations_dimension(location_name)
ON DELETE RESTRICT
ON UPDATE CASCADE;

-- Create a validation check in your pipeline
SELECT 
    COUNT(*) as violation_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM job_postings_fact), 2) as violation_pct
FROM job_postings_fact jpf
LEFT JOIN locations_dimension ld ON jpf.job_location = ld.location_name
WHERE ld.location_id IS NULL AND jpf.job_location IS NOT NULL;

-- Fail the pipeline if violations exceed threshold
-- (Pseudocode in your orchestration tool)
-- IF violation_pct > 0.1 THEN RAISE ERROR
```

## Notes

- **Nulls are intentional:** A null foreign key is *not* a violation if business rules allow it. Know the difference between "missing relationship" and "relationship doesn't apply." Document that expectation in your data contract.

- **Timing matters:** Validate referential integrity *during* the load phase, not after aggregation. Catching the problem when you can still reject the batch is vastly cheaper than discovering it in a dashboard query.

- **Dimension stability:** Foreign keys fail quietly when dimension tables are truncated and reloaded without preserving IDs. Always preserve surrogate keys across refreshes or use natural keys with careful change management.

- **Adjacent skills:** This connects to data contracts (documenting which relationships must hold), SLAs (defining acceptable violation rates), and lineage tracking (understanding where violations originated). Also review ON DELETE/UPDATE cascade rules—they can fix or mask problems depending on your intent.

- **Revisit:** Check your approach when fact tables grow large (validation becomes expensive), when you adopt slowly-changing dimensions (SCD Type 2 breaks simple FK assumptions), or when data sources are external and unreliable (you may need quarantine logic before enforcing constraints).
