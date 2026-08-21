---
date: 2026-08-21
phase: modelling
topic: Activity schema: an event-centric alternative to star schema
---

# Activity schema: an event-centric alternative to star schema

*Data modelling and warehousing*

## Concept

An activity schema organizes data around discrete events or activities rather than entities (like star schema's dimensional approach). Each row represents one thing that happened: a user login, a job posting change, a purchase—with a timestamp and all relevant context denormalized into that row. This differs from star schema, where you might have separate dimension tables for jobs, locations, and salaries that you join at query time.

Activity schema matters when events themselves are the unit of analysis and when context changes over time. Star schema works well for "give me current state," but breaks when you need "what was the salary on posting day?" or "how many active job postings existed last Tuesday?" You end up writing complex slowly-changing-dimension logic or joining multiple historical tables. Activity schema makes temporal and event-driven analysis trivial—the data is already denormalized as it was at that moment.

The tradeoff: redundancy. Activity schema repeats job_title_short and job_location across many rows. But that redundancy buys you self-documenting queries where one table answers most questions without ambiguous joins, and it makes historical context immediate, not reconstructed.

## Practice

**Problem:** You need to find the average salary for remote jobs posted in the last 90 days, filtered to jobs posted *before* a major economic shift (2024-01-15). Star schema forces you to join jobs, locations, and salary tables and handle slowly-changing dimensions. With activity schema, the query is direct:

```sql
SELECT
  AVG(salary_year_avg) AS avg_salary
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY
  AND job_posted_date < '2024-01-15'
;
```

Each row already contains salary, remote status, and posting date *as they were on that event*. No joins, no dimension lookups, no risk of picking the wrong version of a job's title.

## Notes

- **Denormalization is the point, not a bug.** Repeating job_title_short feels wrong if you learned normalization first. Resist that instinct; it's the schema's strength for event queries.
- **Timestamp precision matters.** Without a precise `job_posted_date` (or better, `job_posted_timestamp`), you lose the ability to reconstruct state at any point in time. Make timestamps the first thing you define.
- **Connects to:** event sourcing (activity schema is its data warehouse cousin), slowly-changing dimensions (activity schema avoids the problem), fact tables (activity schema *is* a fact table, just without separate dimensions).
- **Common mistake:** mixing immutable event data with mutable attributes. If job_title_short can change and you want to track that, you need a new row with a new timestamp; don't update the old one.
- **Revisit:** How to handle corrections and late-arriving data. Activity schema assumes events are immutable; decide upfront whether you'll append corrected rows or allow updates, and document that rule.
