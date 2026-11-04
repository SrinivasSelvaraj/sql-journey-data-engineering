---
date: 2026-11-04
phase: reliability
topic: Rollback procedures: reverting failed deployments
---

# Rollback procedures: reverting failed deployments

*Quality, reliability and the professional layer*

## Concept

Rollback procedures are automated or manual processes that revert a deployment to a known-good state when something fails in production. Unlike development, where you can debug and rerun, production deployments affect downstream consumers, reports, and business decisions—a broken transformation silently corrupts data for hours before anyone notices. Rollback is your escape hatch: it stops the bleeding, restores trust, and buys time for root cause analysis without pressure.

A robust rollback strategy requires three things: (1) versioning of code and schema so you know exactly what "good" looked like, (2) backup or immutable history of data (staging tables, snapshots, or transaction logs), and (3) clear ownership and runbooks so the on-call engineer doesn't improvise at 2 AM. Without this, a typo in a WHERE clause or a miscalculated join key becomes a data incident that takes days to unpick.

The difference between a junior pipeline owner and a trusted one is that the junior builds features; the trusted one builds features *that can be safely undone*. This mindset—thinking about failure modes first—is what separates "ships code" from "owns systems."

## Practice

**Problem:** A daily job transformed `job_postings_fact` by applying a salary outlier filter (`salary_year_avg < 500000`), but the filter logic was reversed in production. For 4 hours, legitimate $300k salaries were deleted. How do you rollback?

```sql
-- Step 1: Create immutable staging snapshot before each transformation
CREATE TABLE job_postings_fact_v20250115_0800 AS
SELECT * FROM job_postings_fact;

-- Step 2: Identify the bad run's timestamp range
SELECT COUNT(*), MIN(job_posted_date), MAX(job_posted_date)
FROM job_postings_fact
WHERE salary_year_avg IS NULL OR salary_year_avg > 500000;
-- Result: 0 rows (the outliers were deleted—confirmed corruption)

-- Step 3: Rollback to last known-good version
BEGIN TRANSACTION;
DELETE FROM job_postings_fact;
INSERT INTO job_postings_fact
SELECT * FROM job_postings_fact_v20250115_0800;
COMMIT;

-- Step 4: Validate row counts match pre-deployment
SELECT COUNT(*) FROM job_postings_fact;
-- Compare to logged baseline: should be 150,423 rows, not 146,891

-- Step 5: Log the rollback event for audit
INSERT INTO deployment_log (action, timestamp, affected_rows, reason)
VALUES ('ROLLBACK', NOW(), 3532, 'Outlier filter logic inverted in production');
```

## Notes

- **Snapshot naming is critical:** Use timestamps and version numbers (e.g., `_v20250115_0800`), not descriptive names like `_backup` which get stale and cause confusion during incidents.
- **Rollback ≠ recovery:** Rollback restores code/schema to a safe state; recovery (if needed after rollback) involves notifying downstream teams and potentially re-running dependent jobs.
- **Test rollback procedures in pre-prod.** A rollback that works in staging might fail in production due to locking, size, or permission issues—find that out before you need it.
- **Connect to idempotency:** if your transformations are idempotent (safe to run multiple times), rollback is simpler because you can roll back *and* rerun without worrying about duplicates.
- **Adjacent topics:** deployment orchestration (how you control rollout), change data capture (for incremental rollback), and post-mortem culture (why you rollback without blame, then learn what went wrong).
