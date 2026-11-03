---
date: 2026-11-03
phase: reliability
topic: Reverse lineage: impact analysis of upstream changes
---

# Reverse lineage: impact analysis of upstream changes

*Quality, reliability and the professional layer*

## Concept

Reverse lineage is the practice of understanding what downstream systems, reports, and decisions depend on a given data asset—the inverse of forward lineage (which tracks source → transform → output). When an upstream table, column, or transformation changes, reverse lineage tells you what will break or need revalidation. Without it, you deploy a schema change or fix a calculation bug only to discover three weeks later that a critical dashboard is now wrong, or worse, feeding incorrect data to a pricing algorithm.

This becomes essential once your data platform serves multiple teams. A junior engineer builds a pipeline; a reliable owner knows what else might fail if that pipeline changes. It's the difference between "the ETL works" and "I can safely modify this knowing what downstream impact exists."

Reverse lineage is especially critical in organizations where data ownership is distributed—data science teams, analytics, operations—and where changes propagate silently. Without visibility into reverse dependencies, you create technical debt, fragile pipelines, and eroded trust in data.

## Practice

**Problem:** You discover that `job_postings_fact.salary_year_avg` contains many nulls because upstream source data quality has degraded. You want to set a default value (e.g., median salary by job title) before it reaches consumers. But you need to know: what dashboards, ML models, and downstream tables depend on this column? How will imputation affect their logic?

```sql
-- Build a reverse lineage query: find all downstream dependencies
-- This assumes you have a metadata catalog (e.g., lineage_graph table)

WITH upstream_asset AS (
  SELECT asset_id, asset_name, asset_type
  FROM lineage_metadata
  WHERE asset_name = 'job_postings_fact'
    AND column_name = 'salary_year_avg'
)
SELECT
  d.downstream_asset_name,
  d.downstream_asset_type,  -- table, dashboard, ml_model, report
  d.owner_team,
  d.last_refresh_time,
  STRING_AGG(d.column_dependency, ', ') AS columns_used,
  CASE 
    WHEN d.downstream_asset_type = 'ml_model' THEN 'HIGH'
    WHEN d.downstream_asset_type = 'dashboard' AND d.owner_team = 'Finance' THEN 'HIGH'
    ELSE 'MEDIUM'
  END AS impact_priority
FROM lineage_metadata AS m
INNER JOIN lineage_graph AS lg
  ON m.asset_id = lg.upstream_asset_id
INNER JOIN lineage_metadata AS d
  ON lg.downstream_asset_id = d.asset_id
WHERE m.asset_name = 'job_postings_fact'
  AND m.column_name = 'salary_year_avg'
GROUP BY d.downstream_asset_name, d.downstream_asset_type, d.owner_team, d.last_refresh_time
ORDER BY impact_priority DESC, d.owner_team;
```

This query surfaces all consumers of the column, their priority, and owner contact. Before deploying your null-handling logic, you'd notify impacted teams and validate that the transformation won't break their use cases.

## Notes

- **Common mistake:** Assuming "I'll document it later"—reverse lineage must be captured at pipeline build time (via metadata logging, data catalog tools, or lineage auto-inference), not retrofitted.
- **Common mistake:** Only tracking direct dependencies; a dashboard might depend on a table that depends on your column, making the impact invisible without recursive traversal.
- **Adjacent topic:** Forward lineage (source → target) is often simpler to implement; combine both for complete impact analysis.
- **Worth revisiting:** Lineage metadata governance—who owns the catalog, how stale can it be before decisions become unreliable, how to keep it synchronized with actual code.
- **Practical tools to know:** dbt's `manifest.json`, Collibra, Apache Atlas, custom metadata tables with event-driven updates—all enable reverse lineage queries.
