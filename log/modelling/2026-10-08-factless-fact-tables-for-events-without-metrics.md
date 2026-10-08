---
date: 2026-10-08
phase: modelling
topic: Factless fact tables for events without metrics
---

# Factless fact tables for events without metrics

*Data modelling and warehousing*

## Concept

A factless fact table records events or relationships without aggregatable metrics—the event itself is the measure. Classic examples include student course enrollments, website page visits, or job applications. Instead of summing revenue or counting transactions, you're capturing *that something happened*, preserving the dimensional context around it.

Without a factless fact table, you either denormalize dimensions into an event log (losing query flexibility and exploding storage) or miss the event entirely because you only store aggregates. A properly designed factless fact table lets analysts ask "How many unique candidates applied for remote jobs in Q3?" by joining to job and date dimensions, without pre-computing that specific metric.

The key distinction: if your event has no numerical measure to aggregate, stop trying to invent one (like a meaningless "1" flag). Instead, build a table with surrogate keys pointing to dimensions and a date key, then let the dimensions and counts answer questions.

## Practice

**Problem:** You need to track every job posting event so analysts can query patterns like "Which job titles get posted most often in each location?" or "How posting frequency changed month-to-month?" The current approach stores only the latest job details per ID, losing posting history.

```sql
-- Factless fact table: captures the event of a job being posted
CREATE TABLE job_postings_fact (
    job_posting_id INT PRIMARY KEY,
    job_id INT NOT NULL,
    job_title_key INT NOT NULL,  -- FK to job_title dimension
    location_key INT NOT NULL,   -- FK to location dimension
    work_from_home_key INT NOT NULL,  -- FK to work_flexibility dimension
    posted_date_key INT NOT NULL,  -- FK to date dimension (YYYYMMDD)
    FOREIGN KEY (job_title_key) REFERENCES job_title_dim(job_title_key),
    FOREIGN KEY (location_key) REFERENCES location_dim(location_key),
    FOREIGN KEY (work_from_home_key) REFERENCES work_flexibility_dim(work_from_home_key),
    FOREIGN KEY (posted_date_key) REFERENCES date_dim(date_key)
);

-- Query: postings per job title by month
SELECT 
    jt.job_title_short,
    d.year_month,
    COUNT(*) AS posting_count
FROM job_postings_fact jpf
JOIN job_title_dim jt ON jpf.job_title_key = jt.job_title_key
JOIN date_dim d ON jpf.posted_date_key = d.date_key
GROUP BY jt.job_title_short, d.year_month
ORDER BY d.year_month DESC, posting_count DESC;
```

## Notes

- **Don't add a fake metric:** resisting the urge to add a `posting_count = 1` column keeps the table's intent clear and your star schema honest.
- **Grain matters:** define whether one row = one posting event, one application, or one job-location-date combination; ambiguity kills reproducibility.
- **Connects to conformed dimensions:** factless tables rely on shared dimensions (location, date, job title) across your warehouse; weak dimension governance breaks cross-table analysis.
- **Common mistake—over-normalizing attributes:** store only keys in the fact table; put `salary_year_avg`, `job_title_full`, and descriptive text in their respective dimensions so you can change them without fact table updates.
- **Revisit bridge tables:** if a single job posting applies to multiple locations or titles, consider a bridge dimension instead of duplicating rows, to keep fact grain clean.
