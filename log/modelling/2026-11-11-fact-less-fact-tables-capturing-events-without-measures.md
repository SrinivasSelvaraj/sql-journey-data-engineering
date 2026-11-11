---
date: 2026-11-11
phase: modelling
topic: Fact-less fact tables: capturing events without measures
---

# Fact-less fact tables: capturing events without measures

*Data modelling and warehousing*

## Concept

A fact-less fact table records events or transactions *without numeric measures*—it captures the *occurrence itself* as meaningful data. Instead of summing or averaging values, you're documenting that something happened: a user logged in, a job was posted, an item was viewed. The grain is the event, and the table often contains only dimensional keys and a timestamp.

This matters when the event's existence is the insight. In recruitment analytics, for instance, knowing *which jobs were posted on which dates in which locations* is valuable even if you never aggregate salary. Without this table, you lose the ability to ask "How many unique job titles were posted each week?" or "What's the distribution of posting locations?" You end up reconstructing events from measures or forcing unnatural aggregations.

What breaks: analysts invent fake measures (count = 1, flag = true) to make queries work, or you lose the atomic event record entirely and can only query pre-aggregated snapshots. The schema becomes fragile because it conflates event capture with numerical reporting.

## Practice

**Problem:** You need to analyze job posting *patterns*—which locations get posts on which days, how many unique titles per location per week—but your current fact table only has salary_year_avg as a measure. You can't distinguish "one $100k job posted" from "two $50k jobs posted," and location distribution gets buried.

**Solution:** Create a fact-less fact table to capture the posting event itself:

```sql
CREATE TABLE job_postings_fact (
    job_posting_id INT PRIMARY KEY,
    job_id INT NOT NULL,
    job_title_key INT NOT NULL,
    job_location_key INT NOT NULL,
    job_work_from_home BOOLEAN,
    job_posted_date DATE NOT NULL,
    posted_timestamp TIMESTAMP NOT NULL
    -- No measures: salary, count, or flags
);

-- Now you can answer event-driven questions:
SELECT 
    job_posted_date,
    COUNT(DISTINCT job_posting_id) AS postings_count,
    COUNT(DISTINCT job_title_key) AS unique_titles,
    COUNT(DISTINCT job_location_key) AS locations_active
FROM job_postings_fact
GROUP BY job_posted_date
ORDER BY job_posted_date DESC;

-- Or join to dimensions for richer context:
SELECT 
    l.location_name,
    t.job_title_short,
    COUNT(*) AS posting_frequency
FROM job_postings_fact jpf
JOIN job_title_dim t ON jpf.job_title_key = t.job_title_key
JOIN job_location_dim l ON jpf.job_location_key = l.job_location_key
WHERE jpf.job_posted_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY l.location_name, t.job_title_short
ORDER BY posting_frequency DESC;
```

## Notes

- **Confusing "count = 1" with a measure:** Resist the temptation to add a `count_postings = 1` column. The row *itself* is the count. Use `COUNT(*)` or `COUNT(posting_id)` in queries instead.

- **Grain clarity is critical:** Define explicitly whether each row = one job posting, one application, one click. Ambiguous grain breaks downstream logic.

- **Conforms to Kimball's event fact table pattern:** This is distinct from accumulating snapshots or periodic snapshots; it's purely transactional and atomic. Revisit when modeling user behavior or system events.

- **Bridges event streaming and warehousing:** Fact-less tables often receive late-arriving events or require idempotent loads; connect this to CDC and slowly-changing dimensions.

- **Performance note:** Without measures, these tables compress well and scan fast for event filtering; use appropriate indexes on date and location keys for typical queries.
