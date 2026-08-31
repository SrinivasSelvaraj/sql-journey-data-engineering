---
date: 2026-08-31
phase: modelling
topic: Aggregate table creation and maintenance strategies
---

# Aggregate table creation and maintenance strategies

*Data modelling and warehousing*

## Concept

An aggregate table is a pre-computed, denormalized summary of facts grouped by specific dimensions—for example, average salary by job title and work-from-home status. It trades storage space for query speed: instead of scanning millions of fact rows and grouping on-demand, users hit a small, indexed table that answers the question in milliseconds. This matters when your fact table grows to millions of rows and the same aggregations get queried repeatedly (dashboards, reporting tools, self-service analytics). Without aggregate tables, either queries become slow enough to frustrate users, or the warehouse becomes a bottleneck that only data engineers can unblock. With them, you enable self-service and reduce compute costs.

The challenge is maintenance: aggregate tables must stay in sync with source facts through scheduled refreshes (full or incremental). A stale aggregate table is worse than no aggregate table—it breeds silent data quality issues and eroded trust. You must decide: full refresh nightly, incremental updates hourly, or materialized views that refresh on-demand? The choice depends on how fresh the data needs to be versus how much compute you can afford.

## Practice

**Problem:** Your analytics team runs the same query daily—average salary grouped by job title and work-from-home status. The query scans 2 million rows and takes 45 seconds. Design an aggregate table and a refresh strategy.

```sql
-- Create the aggregate table
CREATE TABLE job_postings_agg (
  job_title_short VARCHAR(100),
  job_work_from_home BOOLEAN,
  avg_salary_year DECIMAL(10,2),
  median_salary_year DECIMAL(10,2),
  job_count INT,
  last_refreshed TIMESTAMP,
  PRIMARY KEY (job_title_short, job_work_from_home)
);

-- Populate via full refresh (run nightly)
INSERT INTO job_postings_agg
SELECT
  job_title_short,
  job_work_from_home,
  ROUND(AVG(salary_year_avg), 2) as avg_salary_year,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as median_salary_year,
  COUNT(*) as job_count,
  CURRENT_TIMESTAMP as last_refreshed
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_title_short, job_work_from_home;

-- Now the dashboard query runs in <1 second
SELECT * FROM job_postings_agg
WHERE job_title_short = 'Data Engineer'
ORDER BY avg_salary_year DESC;
```

## Notes

- **Grain and granularity mismatch**: Choosing dimensions that are too fine (e.g., aggregating by date *and* location *and* title) defeats the purpose; you end up with a table almost as large as the fact table. Start coarse, add dimensions only if queries demand them.

- **Staleness vs. compute tradeoff**: Full refreshes are simple but can be expensive; incremental refreshes (only updating groups touched by new facts) save compute but add complexity. Monitor query freshness SLAs and adjust cadence accordingly.

- **Conformed dimensions**: Aggregate tables only work well if dimension values are stable and well-defined (e.g., job titles are standardized). If job_title_short changes mid-month in the source, your aggregates fragment and become hard to interpret.

- **Documentation is critical**: Name aggregate tables clearly (`_agg`, `_summary`), document the refresh schedule, grain, and any filters applied (e.g., "only jobs with salary data"). A poorly documented aggregate table looks like a bug to the person querying it.

- **Materialized views as alternative**: Many modern warehouses (Snowflake, BigQuery, Redshift Spectrum) support materialized views that auto-refresh and hide complexity from users. These can be preferable to hand-rolled aggregate tables if your platform supports them cost-effectively.
