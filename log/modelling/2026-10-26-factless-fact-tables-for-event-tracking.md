---
date: 2026-10-26
phase: modelling
topic: Factless fact tables for event tracking
---

# Factless fact tables for event tracking

*Data modelling and warehousing*

## Concept

A factless fact table records the *occurrence of an event* without a measurable metric—just dimensions and a timestamp. Unlike a typical fact table that stores `sales_amount` or `quantity_sold`, a factless table captures *that something happened*: a user viewed a product, a job was applied for, a support ticket was opened. This matters because events themselves are often the analysis target: "How many applications per job posting?" or "What's the conversion from view to apply?"

Without factless tables, you either bloat dimension tables with event flags, or you lose the temporal grain entirely. For example, storing "has_been_viewed" as a Boolean on a job posting dimension collapses many views into one state. A factless fact table preserves each occurrence as a row, letting you count, filter, and time-slice naturally in SQL without forcing the warehouse to guess your intent.

The schema you design today determines whether colleagues can self-serve or ask you "what does this column really mean?" Every event should have at least a surrogate key, timestamps, and foreign keys to relevant dimensions.

## Practice

**Problem:** Your job posting table tracks when a job was posted, but you need to understand *application patterns*—specifically, how many unique applicants applied to each job, and whether applications spiked after certain posting dates. The current schema has no way to separate multiple applications from the same user.

```sql
-- Factless fact table: captures each application event
CREATE TABLE job_applications_fact (
  application_id INT PRIMARY KEY,
  job_id INT NOT NULL,
  user_id INT NOT NULL,
  application_date DATE NOT NULL,
  FOREIGN KEY (job_id) REFERENCES job_postings_dim(job_id),
  FOREIGN KEY (user_id) REFERENCES users_dim(user_id)
);

-- Now you can answer: applications per job and trend over time
SELECT
  jp.job_title_short,
  jp.job_location,
  COUNT(DISTINCT jaf.application_id) AS total_applications,
  COUNT(DISTINCT jaf.user_id) AS unique_applicants,
  DATE_TRUNC('week', jaf.application_date) AS application_week
FROM job_applications_fact jaf
INNER JOIN job_postings_dim jp ON jaf.job_id = jp.job_id
GROUP BY jp.job_title_short, jp.job_location, DATE_TRUNC('week', jaf.application_date)
ORDER BY application_week DESC, total_applications DESC;
```

## Notes

- **No metrics, no problem:** Factless tables feel "empty" but they're not—the fact *itself* is the metric. Count rows, count distinct dimensions, measure time between events.
- **Grain is everything:** Each row must represent one atomic event. If you merge two applications into one row, you've broken the grain and lost queryability.
- **Bridge the gap to bridge tables:** When a single event touches many dimensions (e.g., a user applied to a job, and the job has multiple required skills), consider a factless table + bridge table design to avoid fan-out.
- **Timestamp precision matters:** Use `TIMESTAMP` not just `DATE` if you need sub-daily analysis. Event order and sequence gaps become invisible at day granularity.
- **Related concepts to revisit:** Conformed dimensions, slowly changing dimensions (SCD Type 2 for dimension history), and late-arriving facts (events recorded after the posting date).
