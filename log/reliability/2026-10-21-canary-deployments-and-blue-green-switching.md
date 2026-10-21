---
date: 2026-10-21
phase: reliability
topic: Canary deployments and blue-green switching
---

# Canary deployments and blue-green switching

*Quality, reliability and the professional layer*

## Concept

Canary deployments and blue-green switching are deployment strategies that reduce the blast radius of pipeline changes. A **canary deployment** routes a small percentage of traffic (data, jobs, users) to a new version while the majority runs the old version; if metrics degrade, you roll back without widespread impact. **Blue-green switching** maintains two identical production environments—one live (blue), one staged (green)—and cuts traffic over atomically once validation passes. Together, they're the difference between "hoping the change works" and "knowing it works before committing."

These matter most when your pipeline is the source of truth for downstream teams. A bad schema migration, a logic error in a transformation, or a performance regression can corrupt dashboards, trigger false alerts, or delay critical decisions. Without canary or blue-green strategies, you're either deploying at high risk or spending hours in manual rollback. With them, you have a safety net: you see real-world behavior on a subset before exposing everyone.

The cost of skipping this is organizational friction: teams lose confidence in your pipeline, start building defensive checks downstream, or revert to manual processes. You become a bottleneck instead of an enabler.

## Practice

**Problem:** You've rebuilt the `job_postings_fact` table with a new deduplication logic on `job_id` and `job_posted_date`. The old version uses `job_id` alone, sometimes creating duplicates for re-posted jobs. Your change is correct, but you need to validate it against live data before switching all downstream consumers over.

```sql
-- Blue environment (current production)
CREATE TABLE job_postings_fact_blue AS
SELECT DISTINCT ON (job_id)
  job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM raw_job_postings
ORDER BY job_id, job_posted_date DESC;

-- Green environment (new version)
CREATE TABLE job_postings_fact_green AS
SELECT DISTINCT ON (job_id, job_posted_date)
  job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM raw_job_postings
ORDER BY job_id, job_posted_date DESC, job_id;

-- Validation queries before switching
SELECT COUNT(*) AS blue_count FROM job_postings_fact_blue;
SELECT COUNT(*) AS green_count FROM job_postings_fact_green;

SELECT job_id, COUNT(*) AS dup_count FROM job_postings_fact_blue
GROUP BY job_id HAVING COUNT(*) > 1 LIMIT 10;

SELECT job_id, COUNT(*) AS dup_count FROM job_postings_fact_green
GROUP BY job_id HAVING COUNT(*) > 1 LIMIT 10;

-- Once validated, atomic switch
BEGIN;
ALTER TABLE job_postings_fact RENAME TO job_postings_fact_old;
ALTER TABLE job_postings_fact_green RENAME TO job_postings_fact;
COMMIT;

-- Rollback path (keep old version for 24–48 hours)
-- If needed: ALTER TABLE job_postings_fact RENAME TO job_postings_fact_green;
--           ALTER TABLE job_postings_fact_old RENAME TO job_postings_fact;
```

## Notes

- **Metric selection is harder than the mechanics.** You can switch tables, but defining "degradation" takes domain knowledge. How many downstream jobs break? What's the latency cost? Get stakeholders to agree on thresholds before deploying.

- **Canary requires infrastructure discipline.** You need feature flags, traffic routers, or conditional logic in downstream consumers. Blue-green is simpler operationally (two tables, one switch) but more storage-heavy; pick based on your constraints.

- **Observability is the real blocker.** Without logs, row counts, schema diffs, and latency dashboards visible during the canary window, you can't detect problems fast enough. Invest here first.

- **Connects to:** schema versioning, feature flags, rollback testing, and data quality frameworks. All are about decoupling *deployment* from *cutover*.

- **Revisit:** the cost of storage when running blue-green in columnar systems; whether your BI tools and warehouse can handle table aliases or require hard cutover; the human handoff—who monitors the canary window?
