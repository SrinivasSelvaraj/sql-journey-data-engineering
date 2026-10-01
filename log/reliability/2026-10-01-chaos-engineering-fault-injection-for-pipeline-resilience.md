---
date: 2026-10-01
phase: reliability
topic: Chaos engineering: fault injection for pipeline resilience
---

# Chaos engineering: fault injection for pipeline resilience

*Quality, reliability and the professional layer*

## Concept

Chaos engineering is the deliberate injection of failures into your data pipeline to verify it fails gracefully and recovers predictably. Rather than waiting for production failures, you proactively simulate broken sources, schema changes, network timeouts, and data quality issues—then verify your pipeline detects them, alerts appropriately, and either recovers or fails safely. Without this, pipelines silently produce wrong answers: a salary column that stops populating looks identical to correct data until business users notice the anomaly weeks later.

In the quality and reliability phase, chaos engineering separates someone who builds pipelines from someone trusted to own them. The builder assumes happy paths; the owner knows every dependency will fail eventually. You're testing not just code logic but observability: Do your alerts fire? Do your recovery mechanisms work? Can downstream consumers trust the data quality signals you emit?

The most dangerous failures are silent ones—missing data, schema drift, or late arrivals that don't crash the job but corrupt downstream analytics. Chaos engineering forces you to design detection (data quality checks, row counts, schema validation) and response (quarantine, backfill, or manual review) into the pipeline itself, not as an afterthought.

## Practice

**Problem:** Your `job_postings_fact` pipeline ingests job postings daily. A common failure: the source stops sending data entirely for 12 hours due to API outages. Your pipeline runs, finds no new rows, and completes "successfully"—but downstream dashboards show stale data. How do you detect and respond to this?

```sql
-- Add data freshness and volume validation as a pre-insert check
WITH source_validation AS (
  SELECT
    COUNT(*) as row_count,
    MAX(job_posted_date) as latest_date,
    CURRENT_DATE as check_date
  FROM raw.job_postings_api
  WHERE job_posted_date >= CURRENT_DATE - INTERVAL 1 DAY
),
validation_results AS (
  SELECT
    row_count,
    latest_date,
    CASE
      WHEN row_count = 0 THEN 'FAIL: No new rows ingested'
      WHEN latest_date < CURRENT_DATE - INTERVAL 12 HOUR THEN 'FAIL: Data is stale (>12h old)'
      WHEN row_count < 50 THEN 'WARN: Unusually low row count'
      ELSE 'PASS'
    END as validation_status
  FROM source_validation
)
SELECT *
FROM validation_results
WHERE validation_status NOT LIKE 'PASS'
-- If this query returns rows, halt the pipeline and page on-call
-- If it passes, proceed with INSERT into job_postings_fact
```

This catches the silent failure. Pair it with a schema validation job (check for missing columns like `salary_year_avg` or unexpected NULL spikes) and a row-count assertion to ensure you fail loudly, not quietly.

## Notes

- **Silent failure trap:** A pipeline that completes without error but produces wrong data is worse than one that crashes. Design for "fail fast, fail loud" by embedding assertions before critical transforms, not after.
- **Test the alerting, not just the code:** Your chaos test succeeds only if your monitoring catches it. Run a simulation where a source goes offline, then verify the alert fires within your SLA. If the alert doesn't trigger, the detection logic failed.
- **Data quality contracts:** Chaos engineering pairs with schema validation, row-count assertions, and anomaly detection (e.g., salary_year_avg dropping 50% overnight). These form a "data contract" with consumers.
- **Adjacent topics:** Connects to observability (logging, tracing, metrics), rollback strategies (can you restore from a backup or replay?), and ownership culture (who owns the runbook when this fails at 2 AM?).
- **Revisit regularly:** As your pipeline evolves (new sources, new downstream consumers), re-run chaos tests. A failure mode you tested 6 months ago may no longer be relevant; new ones emerge with every schema change.
