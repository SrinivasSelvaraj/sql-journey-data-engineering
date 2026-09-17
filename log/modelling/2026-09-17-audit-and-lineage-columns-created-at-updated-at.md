---
date: 2026-09-17
phase: modelling
topic: Audit and lineage columns: created_at, updated_at
---

# Audit and lineage columns: created_at, updated_at

*Data modelling and warehousing*

## Concept

Audit columns (`created_at`, `updated_at`) are timestamp fields that record when a row entered the warehouse and when it last changed. `created_at` is immutable—set once on insert. `updated_at` is refreshed on every update, enabling you to track data freshness and detect late-arriving facts. Together, they answer critical questions: "Is this metric current?" and "Did something break in the pipeline?"

Without audit columns, you lose visibility into data quality. A stale fact table looks identical to a fresh one. Slowly Changing Dimension (SCD) logic becomes impossible to implement. Debugging pipeline failures becomes guesswork—you won't know if a row changed yesterday or six months ago.

For fact tables especially, these columns are non-negotiable. They let downstream consumers filter to "data loaded in the last 24 hours" or "refreshed since my last query," reducing redundant processing and enabling incremental loads.

## Practice

**Problem:** The `job_postings_fact` table is loaded daily. A BI analyst notices salary data changed for a job posting from last week, but can't tell if it's a data correction, a late-arriving fact, or a pipeline bug. How do you design the schema so the analyst can self-serve this investigation?

```sql
CREATE TABLE job_postings_fact (
  job_id INT,
  job_title_short VARCHAR(100),
  salary_year_avg DECIMAL(10,2),
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(100),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (job_id)
);

-- Analyst query: find what changed and when
SELECT 
  job_id,
  salary_year_avg,
  updated_at,
  DATE(updated_at) AS update_date
FROM job_postings_fact
WHERE job_id = 12345
  AND updated_at >= CURRENT_DATE - INTERVAL 7 DAY
ORDER BY updated_at DESC;

-- Bonus: identify stale records (no refresh in 7 days)
SELECT job_id, job_title_short, updated_at
FROM job_postings_fact
WHERE updated_at < CURRENT_TIMESTAMP - INTERVAL 7 DAY
ORDER BY updated_at ASC;
```

## Notes

- **Timezone matters**: always use UTC (`TIMESTAMP WITH TIME ZONE` or equivalent). A row timestamped in EST vs UTC looks like a data anomaly. Document this in your schema comments.
- **Refresh vs. actual change**: `updated_at` increments on *any* write, including no-op updates. If your pipeline does daily full refreshes, every row updates daily even if nothing changed. Use source `dbt_valid_from` / `dbt_valid_to` or a hash of content columns to detect real changes.
- **SCD Type 2 connection**: audit columns enable tracking of dimensional changes over time. Without them, you can't implement SCD Type 2 (history tables). This is where `created_at` becomes the `dbt_valid_from` equivalent.
- **Common mistake**: setting `updated_at` manually in application code instead of database triggers or pipeline logic. Clock skew, missed updates, and inconsistency result. Default to `CURRENT_TIMESTAMP` and let the system manage it.
- **Adjacent: `dbt_loaded_at`**: in dbt models, the `dbt_snapshot` macro handles audit columns automatically. Understand how dbt's `valid_from` / `valid_to` differ from raw `created_at` / `updated_at`—they serve different audiences (analysts vs. engineers).
