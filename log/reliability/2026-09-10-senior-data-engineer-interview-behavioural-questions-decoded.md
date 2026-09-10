---
date: 2026-09-10
phase: reliability
topic: Senior data engineer interview: behavioural questions decoded
---

# Senior data engineer interview: behavioural questions decoded

*Quality, reliability and the professional layer*

## Concept

Behavioural questions in senior data engineer interviews don't assess what you built—they assess *how you own what you built*. The gap between intermediate and senior is accountability: recognising when a pipeline fails in production at 2am, deciding who gets woken up, and whether you've designed systems that prevent the call in the first place. This is the professional layer—reliability engineering, communication under pressure, and trade-offs between speed and stability.

What breaks without it: teams accumulate technical debt because no one feels responsible for the whole system. Data quality degrades silently. On-call rotations become nightmares because nobody documented failure modes. Junior engineers ship breaking changes because they didn't think through downstream consumers. A senior engineer anticipates these scenarios, builds guardrails, communicates constraints upfront, and takes ownership of the gap between "it works in dev" and "it works reliably for 50 teams".

When it matters most: during outages, when priorities conflict, when you inherit broken systems, when you need to say "no" to a request that sounds simple but isn't, and when a junior asks "why do we do it this way?" and your answer goes beyond "because we always have."

## Practice

**Problem:** Your team owns the `job_postings_fact` table. Yesterday, a job_title_short update changed all remote jobs to NULL instead of TRUE/FALSE in job_work_from_home. The change went live without testing. Three downstream teams use this column for dashboards. You discover it during your code review an hour later. What's your response?

**Solution approach** (and what a senior demonstrates):
1. Immediate: assess blast radius
2. Communication: notify consumers before they query bad data
3. Recovery: rollback or correct, with validation
4. Prevention: design for this scenario next time

```sql
-- 1. ASSESS: How recent is the corruption?
SELECT 
  DATE(job_posted_date) as post_date,
  COUNT(*) as total_rows,
  COUNT(CASE WHEN job_work_from_home IS NULL THEN 1 END) as null_count,
  ROUND(100.0 * COUNT(CASE WHEN job_work_from_home IS NULL THEN 1 END) 
        / COUNT(*), 2) as null_pct
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL '2 DAYS'
GROUP BY DATE(job_posted_date)
ORDER BY post_date DESC;

-- 2. PREVENT (add to your pipeline): data quality gate *before* commit
-- Run this as a pre-publish check; fail the job if thresholds breach
WITH quality_check AS (
  SELECT 
    COUNT(*) as total,
    COUNT(CASE WHEN job_work_from_home IS NULL THEN 1 END) as nulls,
    COUNT(DISTINCT job_work_from_home) as distinct_values
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE
)
SELECT 
  CASE 
    WHEN (SELECT nulls / total FROM quality_check) > 0.05 
      THEN 'ALERT: >5% NULL in job_work_from_home'
    WHEN (SELECT distinct_values FROM quality_check) NOT IN (2, 3) 
      THEN 'ALERT: unexpected distinct values (should be T, F, NULL)'
    ELSE 'PASS'
  END as status;

-- 3. COMMUNICATE: schema to notify consumers
-- You'd send: table, column, time window, expected fix time, workaround query
-- Example workaround for downstream teams:
SELECT 
  job_id, job_title_short,
  CASE 
    WHEN job_work_from_home IS NOT NULL THEN job_work_from_home
    WHEN job_location ILIKE '%remote%' THEN TRUE
    ELSE FALSE 
  END as job_work_from_home_repaired
FROM job_postings_fact
WHERE job_posted_date >= '2024-01-01';
```

## Notes

- **Owning the mistake, not hiding it:** Senior engineers communicate delays and failures to stakeholders immediately. The interview question "tell me about a time you broke production" is testing whether you learned, communicated, and prevented recurrence—not whether you're infallible.
- **Data contracts and SLOs:** A senior thinks in terms of promises to downstream consumers: "this column will never be NULL", "this table updates within 1 hour of source", "we support 12 months of history". These aren't enforced by SQL alone; they're enforced by monitoring, alerting, and honest capacity planning.
- **Distinguish between speed and reliability:** Shipping without tests is fast. Shipping with confidence is senior. Be ready to articulate the cost of skipping validation: "We could merge in 10 minutes or spend 20 minutes adding a data quality check that prevents a 2-hour incident."
- **Adjacent topics:** incident response playbooks, monitoring and alerting thresholds, schema versioning, backwards-compatible changes, on-call rotations, runbooks, and blameless
