---
date: 2026-10-22
phase: reliability
topic: Incident response: runbooks and post-mortem culture
---

# Incident response: runbooks and post-mortem culture

*Quality, reliability and the professional layer*

## Concept

A runbook is a documented procedure for responding to a known failure mode. In data engineering, it bridges the gap between "the pipeline failed" and "we restored service in 15 minutes with zero data loss." Without runbooks, incident response becomes reactive guesswork: people search for logs, argue about root cause, apply untested fixes under pressure, and often make things worse. Post-mortem culture—systematically reviewing what went wrong and updating runbooks—transforms incidents from crises into learning events and prevents repeated failures.

Runbooks matter most when the cost of downtime is high (revenue reporting, compliance data, production recommendations) or when on-call engineers rotate and knowledge cannot live in one person's head. A typical runbook covers: symptom detection (what alerts should fire), immediate triage steps (check logs, validate data volumes, verify downstream dependencies), rollback procedures, and escalation paths. Post-mortems matter equally because they surface the gaps: which runbook steps were unclear, which alerts didn't fire, which assumptions were wrong.

Without this discipline, organizations accumulate technical debt in the form of tribal knowledge. The senior engineer knows the quirks of the ETL scheduler; the junior engineer does not. When that senior engineer is unavailable, the incident response time triples. Worse, the same failure repeats six months later because no one documented why it happened or how to prevent it.

## Practice

**Problem:** Your job_postings_fact table normally receives 500–1000 rows daily. This morning, at 8 AM UTC, the ingest job completed but loaded zero rows. The data warehouse is now missing a full day of job postings. Write a runbook entry that covers immediate triage and a recovery query.

```sql
-- RUNBOOK: Zero-row load in job_postings_fact
-- Symptom: job_postings_fact has no records with job_posted_date = TODAY()
-- Expected daily volume: 500–1000 rows

-- STEP 1: Confirm the problem
SELECT 
  job_posted_date, 
  COUNT(*) as row_count
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 3 DAY
GROUP BY job_posted_date
ORDER BY job_posted_date DESC;

-- STEP 2: Check upstream source table for data
SELECT COUNT(*) as source_row_count, MAX(job_posted_date) as latest_date
FROM job_postings_raw  -- upstream staging table
WHERE job_posted_date = CURRENT_DATE;

-- STEP 3: If source has data but fact table is empty, investigate transformation
-- Common causes: WHERE clause filtering all rows, JOIN dropping all records, NULL in job_id
SELECT 
  COUNT(*) as total,
  COUNTIF(job_id IS NULL) as null_ids,
  COUNTIF(job_title_short IS NULL) as null_titles,
  COUNTIF(job_work_from_home IS NULL) as null_remote
FROM job_postings_raw
WHERE job_posted_date = CURRENT_DATE;

-- STEP 4: Recovery—reload today's data if transformation is confirmed correct
INSERT INTO job_postings_fact
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_work_from_home, 
  job_posted_date
FROM job_postings_raw
WHERE job_posted_date = CURRENT_DATE
  AND job_id IS NOT NULL
  AND job_title_short IS NOT NULL;

-- STEP 5: Validate recovery
SELECT COUNT(*) as rows_loaded, MIN(job_posted_date) as earliest, MAX(job_posted_date) as latest
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE;
```

## Notes

- **Common mistake:** Runbooks written after the fact, by someone who wasn't on-call, and never tested. A runbook you haven't run end-to-end is fiction. Test it in staging; time it; update it.

- **Symptom vs. cause confusion:** "The load is slow" is a symptom. "The source database locked during peak hours" is a cause. Runbooks should cover both—alerting on symptoms, but post-mortems must uncover root causes or you'll fight the same fire forever.

- **Connects to:** observability and monitoring. A runbook is only useful if alerts actually fire. Without dashboards, log aggregation, and SLO definitions, you're debugging blind. Runbooks assume you know *that* something broke; monitoring ensures you know *when*.

- **Post-mortem template matters:** "what happened → why did our systems not prevent it → what changed to fix it → what are we committing to change so it doesn't repeat" keeps retrospectives focused on action, not blame.

- **Revisit after on-call rotation:** After the first engineer new to the team handles an incident using your runbook, ask them: "Was this clear? What did you have to guess?" That feedback improves the runbook and your incident response culture faster than any post-mortem.
