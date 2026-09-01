---
date: 2026-09-01
phase: pipelines
topic: Schema migration in running pipelines without downtime
---

# Schema migration in running pipelines without downtime

*Pipelines and orchestration*

## Concept

Schema migration in running pipelines is the practice of evolving table structure—adding columns, changing types, renaming fields—while data continues flowing through active jobs. Without it, you face two bad choices: stop the pipeline (downtime, data loss risk) or ignore schema drift (silent failures, inconsistent outputs downstream).

The core challenge is that your ETL jobs have compiled expectations. A job expecting `job_postings_fact` to have 6 columns will fail or behave unexpectedly if you add a 7th mid-run. Similarly, downstream consumers (dashboards, ML models, other pipelines) may break if a column vanishes or changes type. True zero-downtime migration requires coordinating changes across producers and consumers, making columns backward-compatible, and validating during rollout.

This matters most in data warehouses where pipelines run 24/7 and schema changes are frequent as business requirements evolve. Without a strategy, you either coordinate painful maintenance windows or accumulate technical debt through schema versioning hacks and brittle null-checks.

## Practice

**Problem:** You need to add a new column `job_salary_currency` (VARCHAR) to `job_postings_fact` because source data now includes salary in multiple currencies. Existing pipelines still write to the table, and downstream BI tools read from it. You cannot afford downtime.

**Solution:**

```sql
-- Step 1: Add column with DEFAULT (non-blocking, allows old pipelines to keep writing)
ALTER TABLE job_postings_fact 
ADD COLUMN job_salary_currency VARCHAR(10) DEFAULT 'USD';

-- Step 2: Deploy new producer code to write job_salary_currency
-- (Old code still writes, new code writes both old and new columns)

-- Step 3: Backfill historical data safely in batches
UPDATE job_postings_fact 
SET job_salary_currency = 'USD' 
WHERE job_salary_currency IS NULL 
  AND job_posted_date < CURRENT_DATE - INTERVAL '7 days'
LIMIT 100000;

-- Step 4: Add NOT NULL constraint only after backfill completes
ALTER TABLE job_postings_fact 
ALTER COLUMN job_salary_currency SET NOT NULL;

-- Step 5: Update downstream consumers (BI tools, dashboards) to use new column
-- Validate results before removing DEFAULT or cleaning up old logic
```

Key principles: add with defaults first, backfill in batches, constrain only when safe, update consumers after validation.

## Notes

- **Dual-write anti-pattern**: writing to both old and new columns simultaneously increases complexity; prefer a short window where old code coexists with new code, then cutover cleanly.
- **Backward compatibility first**: always add columns as nullable with defaults; avoid removing or narrowing types until you're certain no running job depends on the old shape.
- **Test migration scripts in staging**: run your ALTER + backfill logic on a production-scale replica; measure runtime and lock contention before touching prod.
- **Connects to**: feature flags (gate which pipelines use which schema version), schema registry tools (Avro, Protobuf—track evolution), and CDC (change data capture can replay old events with new schema).
- **Revisit**: this interacts tightly with idempotency and replay safety; if a job reruns after a schema change, it must handle both old and new column shapes gracefully.
