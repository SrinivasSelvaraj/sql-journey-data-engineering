---
date: 2026-10-20
phase: reliability
topic: Incident response playbooks and runbooks
---

# Incident response playbooks and runbooks

*Quality, reliability and the professional layer*

## Concept

An incident response playbook is a documented set of steps to diagnose, mitigate, and resolve failures in data pipelines—before they happen. A runbook is the executable version: scripts, queries, dashboards, and decision trees that let you act under pressure. Without them, incident response becomes reactive guessing: you're debugging in production while stakeholders wait, you're repeating the same fixes, and knowledge walks out the door with whoever happened to be on-call.

The difference between building pipelines and owning them is exactly this: builders assume systems work. Owners assume they will fail—and have a plan. A playbook answers: *What could break here?* (schema validation failures, upstream API timeouts, late-arriving data, cardinality explosions). A runbook answers: *What do I do in the next 5 minutes?* (check logs, verify row counts, rollback or forward-fill, notify stakeholders, post-mortem).

This is where data engineering becomes professional. It's the layer where you move from "the pipeline ran" to "the pipeline ran, and if it didn't, here's exactly who knows what to do."

## Practice

**Problem:** Your `job_postings_fact` table loads daily via an overnight batch. One morning, dashboards show zero remote jobs—all `job_work_from_home` values flipped to FALSE. You have 90 seconds to decide: roll back, investigate, or push forward.

**Runbook query set:**

```sql
-- 1. Detect: Compare today's distribution to baseline
SELECT 
  job_work_from_home,
  COUNT(*) as count_today,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) as pct_today
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE
GROUP BY job_work_from_home;

-- 2. Scope: How many rows changed?
SELECT 
  COUNT(DISTINCT job_id) as affected_rows
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE
  AND job_work_from_home = FALSE;

-- 3. Root cause: Check upstream schema
SELECT 
  job_work_from_home,
  COUNT(*) as count_raw
FROM raw_job_postings_staging
WHERE load_date = CURRENT_DATE
GROUP BY job_work_from_home;

-- 4. Decide: If upstream is correct, rollback to yesterday
DELETE FROM job_postings_fact 
WHERE job_posted_date = CURRENT_DATE;

INSERT INTO job_postings_fact
SELECT * FROM job_postings_fact_backup
WHERE job_posted_date = CURRENT_DATE;

-- 5. Verify
SELECT job_work_from_home, COUNT(*) FROM job_postings_fact 
WHERE job_posted_date = CURRENT_DATE GROUP BY 1;
```

## Notes

- **Runbooks live in version control**, not Slack threads or someone's notes. Store them next to your code so they're reviewed, tested, and always current.
- **Playbooks must cover the cascade**: a single-table failure isn't isolated—trace dependencies downstream. Which reports break? Which teams get paged? Who owns the apology?
- **Post-incident reviews aren't punishment**—they're playbook updates. Every incident reveals a gap in your documentation or monitoring.
- **Monitoring and alerting are runbook prerequisites**: you can't execute a runbook if you don't know something broke. Thresholds, anomaly detection, and schema contracts are the tripwire.
- **This connects to observability (logs, metrics, traces), data contracts (schema validation upstream), and SLOs (the "acceptable downtime" your playbook buys you time to fix).**
