---
date: 2026-10-21
phase: reliability
topic: Data contracts: schema, freshness, volume expectations
---

# Data contracts: schema, freshness, volume expectations

*Quality, reliability and the professional layer*

## Concept

A data contract is an explicit agreement between a data producer and consumer about what data will be delivered, how fresh it will be, and how much of it to expect. It codifies three dimensions: **schema** (column names, types, nullability), **freshness** (update frequency, latency SLA), and **volume** (row counts, growth expectations). Without contracts, consumers build pipelines on assumptions. When a producer adds a column, changes a type, delays a refresh by 6 hours, or stops receiving 10% of their upstream records, downstream jobs fail silently or produce wrong results—often discovered only when someone notices stale metrics in a dashboard.

Data contracts transform you from a builder into a *steward*. A steward documents expected behavior upfront, monitors adherence, and alerts when reality diverges. This prevents the scenario where a schema change in source system X cascades through five dependent pipelines, each breaking in different ways. It also creates accountability: if a consumer's job fails because they violated the contract (e.g., assumed non-null values that became sparse), that's their problem. If it fails because the producer breached it, the producer owns the fix.

## Practice

**Problem:** Your `job_postings_fact` table is consumed by three teams: HR Analytics, Executive Reporting, and the recommendation engine. Last month, `salary_year_avg` was NULL for 15% of records (a new recruiter source). HR Analytics broke silently—their bonus distribution report undercounted salaries. The Executive Reporting team's pipeline caught an exception and paused. The recommendation engine degraded gracefully but began showing underpaid roles. You need a contract that would have prevented this.

```sql
-- Data Contract Definition (store as metadata, document, or in dbt schema.yml)
-- Table: job_postings_fact
-- Owner: Recruiting Data Team
-- Consumer SLAs: HR Analytics, Executive Reporting, ML Recommendation Engine

-- SCHEMA CONTRACT
-- job_id: BIGINT, NOT NULL, PK
-- job_title_short: VARCHAR(100), NOT NULL
-- salary_year_avg: NUMERIC(12,2), NOT NULL (>90% non-null required; <10% nulls permitted only if flagged in job_source)
-- job_work_from_home: BOOLEAN, NOT NULL
-- job_posted_date: DATE, NOT NULL
-- job_location: VARCHAR(255), NULLABLE

-- FRESHNESS CONTRACT
-- Refresh frequency: Daily, 6 AM UTC
-- Acceptable latency: Data complete within 24 hours of source ingestion
-- SLA breach threshold: If >2 hours late, trigger Slack alert to #data-incidents

-- VOLUME CONTRACT
-- Expected daily rows: 8,000 ± 20% (6,400 to 9,600)
-- Growth trend: ~2% MoM
-- Volume breach: If daily additions <5,000 or >12,000, mark as anomaly

-- IMPLEMENTATION: Monitoring query
SELECT
  CURRENT_DATE() as check_date,
  COUNT(*) as row_count,
  ROUND(100.0 * SUM(CASE WHEN salary_year_avg IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) as salary_null_pct,
  MAX(job_posted_date) as max_posted_date,
  CASE 
    WHEN COUNT(*) < 6400 THEN 'BREACH: Below min volume'
    WHEN COUNT(*) > 12000 THEN 'BREACH: Above max volume'
    WHEN ROUND(100.0 * SUM(CASE WHEN salary_year_avg IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) > 10 THEN 'BREACH: Salary nulls exceed 10%'
    WHEN CURRENT_TIMESTAMP() > CAST(CURRENT_DATE() AS TIMESTAMP) + INTERVAL '6 hours' + INTERVAL '2 hours' 
      THEN 'BREACH: Refresh lateness >2h'
    ELSE 'PASS'
  END as contract_status
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE()
GROUP BY 1;
```

## Notes

- **Schema nullability is the silent killer:** Avoid "nullable by default." Declare every column's null tolerance upfront; it forces producers to consider data quality early and consumers to handle expected sparsity.
- **Volume baselines require history:** Don't set volume SLAs on day one. Track 2–4 weeks of real data to understand seasonality, source variability, and true growth; then set realistic ± ranges.
- **Freshness != latency:** A daily refresh at 10 AM is fine if consumers expect it by 10 AM. The contract is about meeting the agreed clock, not raw speed.
- **Contracts live in code:** Document in dbt `schema.yml`, a dedicated YAML config, or your metadata tool—not email or Slack. Make them version-controlled and diff-able so breaches are visible.
- **Adjacent topics:** Data quality metrics, SLIs/SLOs, data lineage
