---
date: 2026-10-20
phase: reliability
topic: Application performance monitoring for SQL
---

# Application performance monitoring for SQL

*Quality, reliability and the professional layer*

## Concept

Application performance monitoring (APM) for SQL means systematically tracking query execution time, resource consumption, and failure patterns in production pipelines—not just whether a query "works," but whether it works *reliably and efficiently at scale*. The difference between a junior engineer and someone trusted with a data platform is this: juniors write queries that pass tests; senior engineers write queries they can defend in a 3am incident when the pipeline broke after processing 10x the usual volume.

APM matters the moment your pipeline runs on a schedule or serves stakeholders. A query that joins three tables in 2 seconds might timeout at 5 seconds when data volume doubles. Slow queries starve other jobs of resources. Without monitoring, you discover problems through escalated Slack messages, not proactively. You can't optimize what you don't measure.

Without APM, you lose visibility into: query degradation over time (as data grows), resource bottlenecks (CPU, memory, I/O), failure modes under load, and the cascading impact of one slow query blocking downstream jobs. You become reactive instead of predictive.

## Practice

**Problem:** Your `job_postings_fact` table grows daily. A dashboard query filters by date and joins location data, but response time has crept from 800ms to 4 seconds over two months. You need to identify the bottleneck and establish a baseline.

```sql
-- Establish baseline: measure execution plan and actual row counts
EXPLAIN ANALYZE
SELECT 
    job_title_short,
    COUNT(*) AS posting_count,
    ROUND(AVG(salary_year_avg), 2) AS avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
  AND job_work_from_home = TRUE
GROUP BY job_title_short
ORDER BY posting_count DESC;

-- Identify missing index (common culprit)
CREATE INDEX idx_job_postings_date_wfh 
ON job_postings_fact(job_posted_date, job_work_from_home) 
INCLUDE (job_title_short, salary_year_avg);

-- Re-run EXPLAIN ANALYZE post-index to confirm improvement
-- Log the execution time and plan to a monitoring table
INSERT INTO query_performance_log (query_name, execution_time_ms, row_count, plan_hash, logged_at)
SELECT 
    'job_posting_summary_30d' AS query_name,
    (EXTRACT(EPOCH FROM (NOW() - statement_timestamp())) * 1000)::INT,
    COUNT(*),
    md5(EXPLAIN_PLAN_TEXT),
    NOW()
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '30 days';
```

## Notes

- **Index blindness:** Most SQL degradation is index-related. Use `EXPLAIN ANALYZE` habitually before merging to production; comparing plans across data volumes catches hidden O(n²) joins.
- **Baseline before optimization:** Record execution plans and timing *before* you change anything. Without a baseline, you can't prove your fix worked or detect future regressions.
- **Cardinality assumptions fail silently:** Queries perform well on test data (10K rows) but fail in production (100M rows). APM surfaces this; testing doesn't always.
- **Connects to:** query profiling tools (DataGrip, pgAdmin), slow-query logs, cost-based optimizer understanding, and SLA definition (knowing what "fast enough" means for each pipeline).
- **Revisit regularly:** Add monitoring queries to your dbt tests or orchestration DAG. Make APM part of the deployment checklist, not an afterthought.
