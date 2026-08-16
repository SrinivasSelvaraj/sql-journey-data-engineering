---
date: 2026-08-16
phase: reliability
topic: Incident response and blameless postmortems for data
---

# Incident response and blameless postmortems for data

*Quality, reliability and the professional layer*

## Concept

An incident response process for data systems is the structured approach to detecting, investigating, and resolving data quality failures—not punishing whoever triggered them. A blameless postmortem is the retrospective conversation that follows, focused entirely on system and process gaps rather than individual error. This matters because data incidents are often silent (wrong numbers in dashboards, incorrect ML features, stale tables), meaning they compound before detection. Without a formal response and learning process, you repeat the same failure across different contexts, and team members hide incidents rather than reporting them quickly.

The difference between a pipeline builder and a trusted owner is whether stakeholders believe you'll *tell them* when something breaks. Trust erodes instantly when data teams deflect blame ("the source system changed"), and it recovers only through transparent, pattern-focused postmortems that answer: *What failed? What didn't catch it? What changes prevent recurrence?* This is the professional layer—owning outcomes, not just code.

## Practice

**Problem:** A reporting dashboard shows average salary = $0 for 3 hours before anyone notices. Investigation reveals the ETL job succeeded (no alerting on return code), but a schema change in the source system caused `salary_year_avg` to load as NULL, which aggregated as 0 instead of being excluded.

**Postmortem solution—adding detection and alerting:**

```sql
-- Add data quality checks to the transformation layer
WITH salary_audit AS (
  SELECT
    COUNT(*) as total_rows,
    COUNT(CASE WHEN salary_year_avg IS NULL THEN 1 END) as null_count,
    COUNT(CASE WHEN salary_year_avg = 0 THEN 1 END) as zero_count,
    MIN(salary_year_avg) as min_salary,
    MAX(salary_year_avg) as max_salary
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE
)
SELECT
  CASE
    WHEN null_count > total_rows * 0.05 THEN 'ALERT: Salary NULLs exceed 5%'
    WHEN zero_count > total_rows * 0.02 THEN 'ALERT: Salary zeros exceed 2%'
    WHEN min_salary < 15000 THEN 'ALERT: Minimum salary unusually low'
    ELSE 'OK'
  END as data_quality_status,
  *
FROM salary_audit;

-- Postmortem action items (not blame):
-- 1. Add NOT NULL constraint + default handling in source sync
-- 2. Log this query as an automated check that pages on-call
-- 3. Document schema change detection in runbook
-- 4. Review why the schema change wasn't communicated
```

## Notes

- **Mistake:** Framing postmortems as "who should have caught this?" instead of "what system assumptions broke?" Blame-focused reviews destroy psychological safety and cause teams to hide incidents longer.
- **Mistake:** Confusing "blameless" with "consequence-free." A repeated failure *because* of negligence is different from a novel failure; the postmortem should distinguish between them.
- **Connects to:** monitoring and alerting strategy (what thresholds matter?), data contracts (formalizing assumptions about upstream), and runbook documentation (how do responders act under pressure?).
- **Revisit:** Postmortem effectiveness requires async documentation (Slack threads vanish; write it down), clear action item ownership with deadlines, and follow-up to verify fixes actually shipped.
- **Pattern:** The best data teams have 1–2 postmortems per month per engineer; zero incidents means either no one's looking, or detection is broken.
