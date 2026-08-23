---
date: 2026-08-23
phase: pipelines
topic: Data migration patterns: big bang vs trickle
---

# Data migration patterns: big bang vs trickle

*Pipelines and orchestration*

## Concept

A **big bang migration** moves all data from source to target in a single cutover event; a **trickle migration** runs source and target systems in parallel, gradually shifting traffic or data until cutover. Big bang is faster but riskier—if validation fails, you're reverting everything. Trickle is slower but lets you catch bugs in production-like conditions and roll back incrementally.

The choice matters most when: (1) downtime costs are high, (2) data quality is uncertain, (3) schema mapping is complex, or (4) stakeholders need proof the new system works before full commitment. Without a deliberate strategy, teams either rush a big bang (losing data or discovering bugs post-cutover) or drift into an accidental trickle (running both systems indefinitely, doubling maintenance burden).

Trickle migrations demand strong idempotency and reconciliation: your pipeline must handle duplicate records, out-of-order arrivals, and the ability to replay without corruption. Big bang requires bulletproof validation, a fast rollback plan, and a maintenance window where stakeholders accept darkness.

## Practice

**Problem:** You're migrating `job_postings_fact` from a legacy OLTP system to a cloud warehouse. Legacy uses `job_posted_date` as a transaction timestamp; the new system should use it as a business date. During trickle phase, both systems run live. You need to validate that row counts match and no job_ids are orphaned, then safely merge without duplicates.

```sql
-- Trickle phase: load from source, mark lineage
INSERT INTO job_postings_fact_new
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  CURRENT_TIMESTAMP AS migrated_at,
  'source_system_v1' AS lineage_source
FROM legacy_system.job_postings
WHERE job_posted_date >= '2024-01-01'
ON CONFLICT (job_id) DO UPDATE SET
  updated_at = CURRENT_TIMESTAMP,
  lineage_source = 'incremental_sync'
;

-- Reconciliation query: run daily before cutover
SELECT 'row_count_mismatch' AS validation
FROM (
  SELECT COUNT(*) AS legacy_count FROM legacy_system.job_postings
  WHERE job_posted_date >= '2024-01-01'
) legacy
CROSS JOIN (
  SELECT COUNT(*) AS new_count FROM job_postings_fact_new
  WHERE lineage_source IN ('source_system_v1', 'incremental_sync')
) new
WHERE legacy_count != new_count
UNION ALL
SELECT 'orphaned_ids' AS validation
FROM legacy_system.job_postings l
LEFT JOIN job_postings_fact_new n ON l.job_id = n.job_id
WHERE l.job_posted_date >= '2024-01-01' AND n.job_id IS NULL
;
```

## Notes

- **Idempotency trap:** trickle migrations fail silently if your pipeline doesn't deduplicate; use `ON CONFLICT` or state-based upserts, never blind `INSERT`. Log every attempted duplicate for audit.
- **Big bang speedup:** if you must go big bang, backfill in waves (by `job_posted_date` range), validate each wave independently, then do the final sync-and-flip in minutes, not hours.
- **Reconciliation debt:** trickle requires daily validation queries or they stop running; automate them as tests or alerting rules, not manual spot-checks.
- **Adjacent topics:** data lineage (track where each row came from), feature parity testing (does new system produce same aggregates?), and canary deployments (route 5% of reads to new system before full cutover).
- **Revisit:** checksums and row-level hashing (`MD5(CONCAT(...))`) to catch silent data corruption; plan for the trickle phase to last longer than you expect (3–6 weeks is realistic for high-stakes migrations).
