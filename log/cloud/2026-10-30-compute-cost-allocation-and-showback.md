---
date: 2026-10-30
phase: cloud
topic: Compute cost allocation and showback
---

# Compute cost allocation and showback

*Cloud platforms and storage*

## Concept

Compute cost allocation tracks which team, project, or query consumed cloud resources—and at what cost. In platforms like Snowflake, BigQuery, and Redshift, a single slow query can cost $50–$500 depending on compute time and data scanned. Without allocation, you cannot answer "Why did our bill spike?" or "Which dashboard is draining the budget?"

Showback means displaying these costs back to teams transparently, usually via tagging (labels, namespaces) and metering. You tag queries by department, cost center, or application; the platform logs compute usage; then you aggregate and report it. This creates accountability: engineers see the real cost of their materialized views, daily refreshes, and exploratory queries.

Without cost allocation, cloud spend becomes a black box. Teams over-provision, run inefficient joins unchecked, and data platforms become seen as unlimited resources rather than shared cost centers. Allocation forces a contract: know your query plan, monitor your slot usage, and justify expensive transformations.

## Practice

**Problem:** Your organization has multiple job posting domains (sales, engineering, HR). You need to track compute cost per domain and identify which domain's queries are slowest and most expensive.

```sql
-- Tag queries by domain and track compute usage
-- Assume your platform logs query_id, query_text, bytes_scanned, execution_time_seconds, user, timestamp

WITH query_metadata AS (
  SELECT
    query_id,
    CASE
      WHEN query_text ILIKE '%sales%' OR user LIKE 'sales_%' THEN 'Sales'
      WHEN query_text ILIKE '%engineering%' OR user LIKE 'eng_%' THEN 'Engineering'
      ELSE 'HR'
    END AS domain,
    user,
    bytes_scanned,
    execution_time_seconds,
    TIMESTAMP_TRUNC(query_start_time, HOUR) AS query_hour
  FROM query_logs
  WHERE query_start_time >= CURRENT_DATE - 7
),
cost_estimate AS (
  SELECT
    domain,
    query_hour,
    COUNT(*) AS query_count,
    ROUND(SUM(bytes_scanned) / POW(10, 9), 2) AS gb_scanned,
    ROUND(SUM(execution_time_seconds) / 3600, 2) AS compute_hours,
    -- Example: $4 per compute hour (adjust to your platform)
    ROUND(SUM(execution_time_seconds) / 3600 * 4, 2) AS estimated_cost_usd,
    ROUND(AVG(execution_time_seconds), 1) AS avg_execution_seconds
  FROM query_metadata
  GROUP BY domain, query_hour
)
SELECT
  domain,
  query_hour,
  query_count,
  gb_scanned,
  compute_hours,
  estimated_cost_usd,
  avg_execution_seconds
FROM cost_estimate
ORDER BY query_hour DESC, estimated_cost_usd DESC;
```

## Notes

- **Tagging discipline is foundational**: without consistent job/user/query labels, allocation is guesswork. Enforce naming conventions (e.g., `app:dashboards:retention`, `team:analytics`) at ingest time.
- **Understand your platform's metering**: BigQuery charges by data scanned (regardless of cache hits); Snowflake charges by compute credits; Redshift by node hours. Costs scale differently; a cached query can be free on one platform and half-price on another.
- **Connect cost to query plans**: a slow query is often a full table scan or cartesian join. Use `EXPLAIN` and cost allocation together—slow ≠ expensive, but slow usually means you'll find waste.
- **Showback requires visualization**: raw numbers in SQL don't change behavior. Push costs to a BI tool or Slack dashboard so teams see them weekly. Anonymized peer comparison ("Your domain is 30% above average") drives action.
- **Revisit quota and reserved capacity**: once you know what you're spending, consider reserved slots (Snowflake, BigQuery) or pre-purchased compute to lock in 20–40% discounts. Cost allocation makes the ROI case clear.
