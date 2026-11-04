---
date: 2026-11-04
phase: reliability
topic: Continuous deployment: blue-green and canary releases
---

# Continuous deployment: blue-green and canary releases

*Quality, reliability and the professional layer*

## Concept

Blue-green deployment runs two identical production environments in parallel. The "blue" environment serves live traffic while "green" is staged with new code. Once green passes validation, traffic switches instantly to it; blue becomes the standby. This matters because data pipelines are invisible until they fail—a bad transformation can corrupt months of downstream analytics before anyone notices. Without blue-green, you deploy directly to production, and a single miscalculation (like a schema change or incorrect join logic) affects every dependent dashboard and model simultaneously.

Canary releases are more granular: you route a small percentage of traffic (5–10%) to the new version while most users stay on the old one. If error rates spike or data quality checks fail, the canary is automatically rolled back; if stable, traffic gradually increases. For data pipelines, this means running the new ETL logic in parallel on a subset of tables or time windows, comparing outputs against the old version, before full cutover. The trade-off is higher operational complexity but safer discovery of edge cases.

Both patterns address the same risk: production is where you learn the hardest lessons. Without them, you own the blast radius.

## Practice

**Problem:** You're deploying a new job_postings_fact table that adds a `salary_band` column (derived from `salary_year_avg`) to support faster filtering in dashboards. The column logic is new—you must validate it produces correct bands without breaking existing queries before committing fully.

```sql
-- Blue environment: existing production query
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY;

-- Green environment: new deployment with salary_band logic
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CASE
    WHEN salary_year_avg < 50000 THEN 'entry'
    WHEN salary_year_avg < 100000 THEN 'mid'
    WHEN salary_year_avg < 150000 THEN 'senior'
    ELSE 'executive'
  END AS salary_band
FROM job_postings_fact_green
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY;

-- Validation query: compare row counts and null distribution before cutover
SELECT 
  'blue' AS environment,
  COUNT(*) AS row_count,
  COUNT(DISTINCT job_id) AS unique_jobs,
  SUM(CASE WHEN salary_year_avg IS NULL THEN 1 ELSE 0 END) AS null_salaries
FROM job_postings_fact
UNION ALL
SELECT 
  'green' AS environment,
  COUNT(*) AS row_count,
  COUNT(DISTINCT job_id) AS unique_jobs,
  SUM(CASE WHEN salary_year_avg IS NULL THEN 1 ELSE 0 END) AS null_salaries
FROM job_postings_fact_green;
```

After validation passes, switch read permissions from `job_postings_fact` to `job_postings_fact_green`, then rename green to blue.

## Notes

- **Schema changes are silent killers:** A new NOT NULL column without a default will break downstream INSERT statements. Always validate with actual downstream consumers before switching, not just the new table alone.

- **Canary + observability are inseparable:** You cannot safely route 5% of traffic to a new pipeline without metrics dashboards showing error rates, data freshness, and row-count anomalies in real time. This is where alerting rules live.

- **Cutover windows matter:** Deploy blue-green during low-traffic periods if you can. For 24/7 pipelines, ensure your validation suite runs in <5 minutes so decision-making doesn't stall the team.

- **Version the table, not the logic:** Naming `job_postings_fact_blue` and `job_postings_fact_green` is simpler than schema versioning. Pair this with a metadata table tracking which is "current" so applications read from a single logical table.

- **Rollback must be rehearsed:** A cutover is only safe if you've tested rolling back. Can you revert in 2 minutes if the new logic produces wrong salary bands? Practice this in staging first; it builds trust.
