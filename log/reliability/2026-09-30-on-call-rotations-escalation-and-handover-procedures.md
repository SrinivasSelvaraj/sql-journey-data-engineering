---
date: 2026-09-30
phase: reliability
topic: On-call rotations: escalation and handover procedures
---

# On-call rotations: escalation and handover procedures

*Quality, reliability and the professional layer*

## Concept

On-call rotations formalize who is responsible for a data system at any given time, and escalation procedures define what happens when that person cannot resolve an incident alone. Handover procedures ensure context—alert thresholds, recent deployments, known issues, customer impacts—transfers cleanly between shifts. Without this structure, incidents create confusion (who owns this?), delayed responses (waiting for the right person to wake up), and knowledge loss (the person who understood the schema left).

Escalation isn't just "call the senior engineer." It's a decision tree: threshold for auto-escalate (e.g., >1 hour unresolved), who escalates to whom based on the nature of the failure (data quality vs. infrastructure vs. compliance), and communication protocol (Slack thread, then call, then page manager). Handover procedures capture the context: "Pipeline X has been noisy since the schema change on Tuesday. If you see >5% null rate on `job_location`, check the upstream API first before rolling back."

This layer separates builders from owners. A builder writes working code; an owner ensures it stays working when they're asleep, and that the next shift knows what to watch for.

## Practice

**Problem:** The `job_postings_fact` pipeline has started producing incomplete rows—`salary_year_avg` is NULL for 8% of new posts, up from 0.3% last week. Your on-call engineer notices the alert 45 minutes after it fired. She checks the logs, finds the upstream ETL succeeded, and suspects a schema drift in the source system. She needs to escalate and document the handover for the next shift.

```sql
-- Step 1: Quantify the scope (on-call isolation check)
SELECT 
  DATE_TRUNC('hour', job_posted_date) AS hour_posted,
  COUNT(*) AS total_rows,
  SUM(CASE WHEN salary_year_avg IS NULL THEN 1 ELSE 0 END) AS null_salary_count,
  ROUND(100.0 * SUM(CASE WHEN salary_year_avg IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_pct
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE_TRUNC('hour', job_posted_date)
ORDER BY hour_posted DESC;

-- Step 2: Escalation trigger (decision logic)
-- IF null_pct > 5% AND hour_posted < incident_start - 2 hours → escalate to data quality lead
-- IF null_pct > 10% AND still_rising → page on-call manager

-- Step 3: Handover documentation query (context for next shift)
SELECT 
  'Last 4 clean pipeline runs:',
  job_posted_date,
  COUNT(*) AS row_count,
  MIN(salary_year_avg) AS min_salary,
  MAX(salary_year_avg) AS max_salary,
  COUNT(DISTINCT job_location) AS unique_locations
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '14 days'
  AND salary_year_avg IS NOT NULL
GROUP BY job_posted_date
ORDER BY job_posted_date DESC
LIMIT 4;

-- Step 4: Known issue documented for handover
-- HANDOVER NOTE: 
-- - Failure window: 2024-01-15 14:00 UTC to present
-- - Root cause hypothesis: upstream API schema change (confirm with API team)
-- - Temporary fix: reprocess failed batches after validation
-- - Full fix: requires upstream contract update (assigned to Eng Lead, ETA 24h)
-- - Watch: if null_pct drops below 2%, mark resolved; if rises, immediate escalation
```

## Notes

- **Escalation delay is a metric.** Track it: time from alert fire to escalation decision. Targets: <15 min for critical, <30 min for high. Delays compound—a 45-minute wait often means someone else is sleeping through a growing problem.

- **Handover templates prevent oral history.** Use a lightweight structured handover: (1) current status, (2) recent changes, (3) known flakiness, (4) what to watch, (5) who to call next. Slack threads or a dedicated "notes" table work; unstructured context dies with the shift.

- **Escalation policies must be written and drilled.** If your team argues about who owns what during an incident, your escalation procedure doesn't exist. Make it explicit and practice at least monthly (even fake incidents).

- **Handover connects to observability.** Without precise alerting and logging, you cannot handover effectively. "Something feels wrong" is not a handover note. Metrics, thresholds, and change logs enable confident transitions.

- **Revisit after blameless postmortems.** Every incident where handover failed or escalation was delayed should trigger a procedure update. The rotation structure is not static; it evolves with your system's brittleness.
