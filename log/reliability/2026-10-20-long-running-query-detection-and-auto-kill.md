---
date: 2026-10-20
phase: reliability
topic: Long-running query detection and auto-kill
---

# Long-running query detection and auto-kill

*Quality, reliability and the professional layer*

## Concept

Long-running query detection and auto-kill is a mechanism to identify and terminate queries that exceed acceptable execution thresholds—typically minutes rather than hours. Without it, a single runaway query (malformed JOIN, missing index, Cartesian product) can monopolize database resources, starve other jobs, and consume cloud credits invisibly. This is especially critical in shared data warehouses where multiple pipelines compete for compute.

The difference between a hobbyist pipeline and a production system is that professionals assume queries *will* misbehave and build guardrails. Auto-kill prevents a typo in a transformation from cascading into a $10k+ incident. It's also a form of observability—a killed query is a signal that your logic or data assumptions have changed.

Most modern data warehouses (Snowflake, BigQuery, Redshift) offer statement timeout settings at the session or warehouse/slot level. The discipline is setting sensible limits per job type (exploratory queries vs. scheduled ETL), monitoring what actually gets killed, and treating each kill as a debugging opportunity, not just a nuisance.

## Practice

**Problem:** You're loading a fact table of job postings. A new analyst's exploratory query joins `job_postings_fact` to itself without proper aggregation, creating a 900M-row Cartesian product. The query runs unchecked, locks the table, and blocks your nightly refresh pipeline. How do you prevent this?

```sql
-- Set statement timeout at session level (Snowflake example)
ALTER SESSION SET STATEMENT_TIMEOUT_IN_SECONDS = 300;

-- Or use a warehouse-level timeout for all jobs
ALTER WAREHOUSE analytics_wh SET STATEMENT_TIMEOUT_IN_SECONDS = 600;

-- Safe exploratory query with explicit aggregation and LIMIT
SELECT 
  jp1.job_title_short,
  COUNT(DISTINCT jp2.job_id) as related_postings
FROM job_postings_fact jp1
INNER JOIN job_postings_fact jp2
  ON jp1.job_title_short = jp2.job_title_short
  AND jp2.job_posted_date > jp1.job_posted_date
WHERE jp1.job_posted_date >= CURRENT_DATE - 30
GROUP BY jp1.job_title_short
LIMIT 1000;
```

The timeout kills uncontrolled cartesian joins automatically. The query itself uses aggregation and date filtering to keep result sets bounded.

## Notes

- **Timeout tuning is iterative**: Set conservatively (5–10 min for ETL), then adjust based on what's actually killed. A killed production job means your SLA is too tight.
- **Distinguish job types**: exploratory work (30s–2min), scheduled pipelines (5–15min), backfill jobs (1–6hr). Use role-based or tag-based timeouts, not one global number.
- **Connected to resource governance**: timeouts are a backstop; true health requires query profiling, index strategy, and partitioning. Killing a query is damage control, not design.
- **Log and alert on kills**: capture which queries timeout, how often, and why. A pattern of timeouts on the same query is a refactoring signal.
- **Revisit: query optimization fundamentals** (execution plans, predicate pushdown), **alerting and monitoring** (detecting cascading failures), and **cost attribution** (which job/user is burning credits).
