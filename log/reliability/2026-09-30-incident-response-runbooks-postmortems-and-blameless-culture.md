---
date: 2026-09-30
phase: reliability
topic: Incident response: runbooks, postmortems and blameless culture
---

# Incident response: runbooks, postmortems and blameless culture

*Quality, reliability and the professional layer*

## Concept

Incident response is the difference between a pipeline that works and a pipeline you can trust at 2 AM. A **runbook** is a living document—step-by-step instructions for detecting, diagnosing, and resolving known failure modes. A **postmortem** is a structured analysis after an incident, focused on systems, not blame. Together, they form muscle memory: when the data warehouse goes silent, your team doesn't panic; they follow the runbook. When it fails in a new way, the postmortem captures what happened so the next person learns from it without shame.

Without runbooks, every incident becomes an ad-hoc firefight. Without postmortems, you repeat the same failures. Without blameless culture, people hide incidents instead of reporting them. The professional distinction is this: junior engineers own their code; senior engineers own their failures. They document them, they learn from them, and they make them visible so others don't repeat them. This is how you scale trust.

Blameless culture doesn't mean no accountability—it means the primary question is "why did the system allow this?" not "who made the mistake?" A data engineer who silently fixes a truncated job_postings_fact table and doesn't report it is a liability. One who documents the incident, identifies the root cause (missing constraint, insufficient alerts), and updates the runbook is the person you promote.

## Practice

**Problem:** Your job_postings_fact table is loaded nightly at 01:00 UTC. At 06:00 UTC, stakeholders report salary data is NULL for all records loaded after midnight. No alert fired. You have no runbook. What do you do?

**Solution runbook + monitoring:**

```sql
-- 1. DETECTION: Add this alert (runs hourly after load)
SELECT COUNT(*) as null_salary_count
FROM job_postings_fact
WHERE job_posted_date = CURRENT_DATE
  AND salary_year_avg IS NULL;
-- Alert if > 10% of today's records

-- 2. DIAGNOSIS: Quick health check
SELECT 
  job_posted_date,
  COUNT(*) as record_count,
  COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) as null_count,
  ROUND(100.0 * COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) / COUNT(*), 2) as null_pct
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - 2
GROUP BY job_posted_date
ORDER BY job_posted_date DESC;

-- 3. ROOT CAUSE: Check upstream source
SELECT job_id, salary_year_avg
FROM staging.job_postings_raw
WHERE job_posted_date = CURRENT_DATE
LIMIT 100;

-- 4. REMEDIATION: If source is clean but load failed, reload
INSERT INTO job_postings_fact
SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
FROM staging.job_postings_raw
WHERE job_posted_date = CURRENT_DATE
  AND job_id NOT IN (SELECT job_id FROM job_postings_fact WHERE job_posted_date = CURRENT_DATE);

-- 5. POSTMORTEM: Capture this
-- Root cause: ETL script used COALESCE(salary, 0) then didn't catch NULL after transform
-- Fix: Add schema validation & NOT NULL constraint
-- Prevention: Add data quality test before insert
ALTER TABLE job_postings_fact 
ADD CONSTRAINT salary_not_null CHECK (salary_year_avg IS NOT NULL OR job_title_short LIKE '%Unpaid%');
```

## Notes

- **Common mistake:** Writing runbooks for hypothetical disasters instead of the three things that actually break every quarter. Start with real incidents, then generalize.
- **Postmortem pitfall:** Focusing on the human error instead of the missing guardrail. "Engineer didn't notice" points to alerting failure; "engineer was tired" blames and teaches nothing.
- **Blameless ≠ blameless:** There's a difference between a systemic gap and willful negligence. Blameless culture applies to accidents; accountability still applies to corners cut.
- **Connects to:** On-call rotations, alert fatigue management, data contract testing, and observability. A runbook is useless without monitoring; postmortems are useless without follow-up action tracking.
- **Worth revisiting:** Incident severity classifications, who owns which systems, and how often to run postmortem drills on old incidents to keep knowledge fresh across rotating teams.
