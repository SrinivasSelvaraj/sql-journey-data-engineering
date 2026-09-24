---
date: 2026-09-24
phase: cloud
topic: Schema registry and metadata store costs
---

# Schema registry and metadata store costs

*Cloud platforms and storage*

## Concept

A schema registry is a centralized metadata store that tracks table structures, field types, and data lineage across your data platform. It sits between your raw data sources and consumption layers, acting as the single source of truth for "what columns exist, what type are they, and who owns them." In cloud platforms like Snowflake, BigQuery, or Databricks, this metadata is stored separately from compute, and accessing it has real costs—each schema lookup, column discovery query, or lineage traversal can incur API calls or warehouse scans.

Without a schema registry, teams either hardcode column names in ETL logic (brittle and slow to debug when schemas change) or run exploratory queries repeatedly to understand table structure (expensive and error-prone). When a source system adds a column, downstream jobs break silently or data quality checks fail without context. The cost problem emerges when you have hundreds of tables and dozens of jobs: every job start-up that introspects schemas, every data catalog scan, every lineage lookup compounds across your platform.

## Practice

**Problem:** You're building a job board analytics pipeline. The `job_postings_fact` table is used by five downstream jobs. When the source system added a `job_salary_currency` column last week, two of your jobs failed silently (they filtered it out), and a third job's performance degraded because it was now scanning an extra column it didn't need. You want to detect schema changes early and document which jobs depend on which columns.

```sql
-- Schema registry pattern: capture and version your schemas
CREATE TABLE IF NOT EXISTS schema_registry (
  table_name STRING,
  column_name STRING,
  data_type STRING,
  is_nullable BOOLEAN,
  ordinal_position INT,
  schema_version INT,
  captured_at TIMESTAMP,
  job_dependencies STRING  -- JSON list of downstream jobs
);

-- Insert the current schema for job_postings_fact
INSERT INTO schema_registry
SELECT
  'job_postings_fact' AS table_name,
  column_name,
  data_type,
  is_nullable,
  ordinal_position,
  1 AS schema_version,
  CURRENT_TIMESTAMP AS captured_at,
  '["salary_analysis_job", "location_aggregator", "posting_velocity_dashboard"]' AS job_dependencies
FROM information_schema.columns
WHERE table_schema = 'analytics' AND table_name = 'job_postings_fact'
ORDER BY ordinal_position;

-- Detect schema drift: compare current vs. registered
SELECT
  c.column_name,
  c.data_type,
  CASE WHEN sr.column_name IS NULL THEN 'ADDED' 
       WHEN c.column_name IS NULL THEN 'REMOVED' 
       ELSE 'MODIFIED' END AS change_type
FROM information_schema.columns c
FULL OUTER JOIN schema_registry sr
  ON c.column_name = sr.column_name 
  AND sr.table_name = 'job_postings_fact'
  AND sr.schema_version = (SELECT MAX(schema_version) FROM schema_registry WHERE table_name = 'job_postings_fact')
WHERE c.table_schema = 'analytics' AND c.table_name = 'job_postings_fact';
```

## Notes

- **Cost trap:** Running `DESCRIBE TABLE` or `INFORMATION_SCHEMA` queries on every job start-up across 100+ jobs wastes credits. Cache schemas in a lightweight table and refresh on a schedule (hourly or event-driven) instead.
- **Silent failures:** Schema drift (added/removed columns) doesn't always break jobs—it silently changes results. A schema registry with version tracking catches this before analytics break.
- **Connects to:** data lineage, data contracts (defining which jobs depend on which columns), and cost optimization strategies like partition pruning and column projection.
- **Common mistake:** Conflating the schema registry with the data catalog. A registry is *transactional* (versions, strict), while a catalog is *searchable* (tags, descriptions). You often need both.
- **Revisit:** When scaling to 500+ tables, consider external tools (Confluent Schema Registry, Apache Atlas, or cloud-native options like Collibra) rather than rolling your own—the metadata query cost and staleness risk grows quickly.
