---
date: 2026-08-30
phase: modelling
topic: Accumulating snapshot facts for multi-stage processes
---

# Accumulating snapshot facts for multi-stage processes

*Data modelling and warehousing*

## Concept

An accumulating snapshot fact table captures multiple milestones or stages of a single business process in one row, with columns for each stage's date and measured values. Unlike transaction facts (one row per event) or periodic snapshots (one row per time period), accumulating snapshots let you track the complete lifecycle—application received, interview scheduled, offer made, accepted—without reconstructing the timeline across multiple tables.

This matters when stakeholders need to answer "how long did each stage take?" or "what percentage of candidates converted at each funnel step?" without joining three tables and writing window functions. A hiring pipeline, order fulfillment, or insurance claim process all benefit: you see the entire journey in one row, with explicit stage dates and values that stay immutable.

Without accumulating snapshots, you either lose the grain (overwriting dates as stages complete, breaking historical analysis) or fragment the story (querying transactions across tables, making simple questions expensive and schema intent opaque).

## Practice

**Problem:** You need to report average time-to-hire by job title, showing how many days elapsed from posting to offer acceptance. Job postings move through stages (posted → applications received → interviews scheduled → offers made → offers accepted). Multiple teams query this independently, and you want them to trust a single source.

```sql
CREATE TABLE job_postings_accumulating_fact (
  job_id INT PRIMARY KEY,
  job_title_short VARCHAR(100),
  salary_year_avg DECIMAL(10, 2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100),
  -- Accumulating snapshot stage dates
  applications_received_date DATE,
  interviews_scheduled_date DATE,
  offers_made_date DATE,
  offers_accepted_date DATE
);

-- Query: average days-to-hire by title
SELECT
  job_title_short,
  ROUND(AVG(CAST(COALESCE(offers_accepted_date, CURRENT_DATE) - job_posted_date AS NUMERIC)), 1) 
    AS avg_days_to_hire,
  COUNT(*) AS total_postings
FROM job_postings_accumulating_fact
GROUP BY job_title_short
ORDER BY avg_days_to_hire DESC;
```

## Notes

- **Null handling:** Stage dates are NULL until that stage occurs. Use `COALESCE(stage_date, CURRENT_DATE)` for in-progress pipelines, but document whether NULL means "not yet" or "will never."
- **Immutability is critical:** Once a date column is populated, it should never change. If a candidate rejects an offer then accepts later, you need a new row or a separate re-activation fact; don't overwrite `offers_accepted_date`.
- **Connects to:** conformed dimensions (job_title, location should live in dims), slowly changing dimensions (if job titles evolve), and fact table grain (define it explicitly: one row per posting, regardless of outcome).
- **Common trap:** confusing accumulating snapshots with periodic snapshots (e.g., "daily hiring status"). Accumulating is event-driven; periodic is time-driven. Pick one per use case.
- **Revisit when:** adding a new stage (e.g., background checks) or changing stage definitions. Document the effective date of schema changes so future you knows why columns exist.
