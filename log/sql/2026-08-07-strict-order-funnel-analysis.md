---
date: 2026-08-07
phase: sql
topic: Strict-order funnel analysis
---

# Strict-order funnel analysis

*SQL for analytics and engineering*

## Concept

Strict-order funnel analysis tracks whether users or entities complete a sequence of events in a *specific order* without requiring consecutive timing. For example, a candidate viewing a job posting, then applying, then interviewing—but the interview can happen days after the application. Without strict ordering, you might count a candidate who interviewed *before* applying, which breaks your business logic.

The key challenge is ensuring events are matched within each step only to rows that have already completed the previous step. A common pitfall is using window functions or self-joins incorrectly, leading to cartesian products or counting the same entity multiple times. You must isolate each funnel stage sequentially: first filter for step 1, then for each qualifying entity, filter for step 2 *after* step 1's timestamp, and so on.

This matters for conversion metrics (signup → trial → paid), recruitment workflows, and onboarding tracking. Without strict ordering, you'll over-count or under-count funnels, producing misleading conversion rates that mislead product and business decisions.

## Practice

**Problem:** Given a schema of job posting events (view, apply, interview), count how many candidates completed the funnel in strict order: viewed a job, then applied to the same job, then interviewed. Return the count of candidates who completed all three steps in order.

Assume you have: `events_fact(candidate_id, event_type, job_id, event_timestamp)`

```sql
WITH step_1_views AS (
  SELECT DISTINCT candidate_id, job_id, event_timestamp AS view_time
  FROM events_fact
  WHERE event_type = 'view'
),
step_2_applies AS (
  SELECT v.candidate_id, v.job_id, v.view_time, e.event_timestamp AS apply_time
  FROM step_1_views v
  INNER JOIN events_fact e
    ON v.candidate_id = e.candidate_id
    AND v.job_id = e.job_id
    AND e.event_type = 'apply'
    AND e.event_timestamp > v.view_time
),
step_3_interviews AS (
  SELECT a.candidate_id, a.job_id, a.view_time, a.apply_time, e.event_timestamp AS interview_time
  FROM step_2_applies a
  INNER JOIN events_fact e
    ON a.candidate_id = e.candidate_id
    AND a.job_id = e.job_id
    AND e.event_type = 'interview'
    AND e.event_timestamp > a.apply_time
)
SELECT COUNT(DISTINCT candidate_id) AS completed_funnel_count
FROM step_3_interviews;
```

## Notes

- **INNER JOIN, not LEFT:** Each step must use INNER JOIN to enforce that only entities reaching that milestone flow forward. LEFT JOIN silently creates NULL rows and inflates counts.
- **Timestamp ordering is critical:** The `WHERE` clause filtering on event_timestamp (e.g., `e.event_timestamp > v.view_time`) enforces strict sequence. Forgetting this is the #1 mistake—you'll count any view + apply + interview, regardless of order.
- **DISTINCT early:** Use `DISTINCT` in early CTEs to avoid duplicate rows from multiple events of the same type, which can cause downstream cartesian products.
- **Related: cohort analysis, retention curves, attribution modeling.** Funnel analysis is the foundation for understanding user journeys; retention builds on identifying cohorts that cleared each stage.
- **Query plan watch:** With large event tables, joins on (candidate_id, job_id, event_timestamp) can be expensive. Ensure indexes exist on (candidate_id, job_id, event_type, event_timestamp) and consider partitioning by date if the table is massive.
