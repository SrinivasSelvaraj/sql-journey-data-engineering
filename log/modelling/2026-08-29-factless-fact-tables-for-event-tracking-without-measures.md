---
date: 2026-08-29
phase: modelling
topic: Factless fact tables for event tracking without measures
---

# Factless fact tables for event tracking without measures

*Data modelling and warehousing*

## Concept

A factless fact table records events or relationships without numeric measures—it captures *that something happened*, not *how much*. Instead of summing or aggregating, you join it to dimension tables to answer questions like "which users clicked which products on which dates?" or "which jobs were posted with which skill requirements?" This matters when your business questions are about co-occurrence, sequences, or categorical combinations rather than totals or averages.

Without factless tables, you either denormalize data (mixing job attributes with posting events, making updates brittle) or force every query writer to reconstruct the relationships themselves (creating inconsistency and tribal knowledge). A factless table is your single source of truth for *what happened and when*—it's the scaffolding that lets dimensions change independently while the event history remains stable.

## Practice

**Problem:** Your analytics team needs to answer "How many job postings require both Python and SQL, posted remote-only in each month?" The current flat table mixes job metadata with skill requirements; skills are comma-separated strings. Every analyst writes different parsing logic, and adding a new skill requires a table rebuild.

**Solution:** Create a factless fact table linking jobs, skills, and posting date; join to dimensions for filtering and grouping.

```sql
-- Factless fact table
CREATE TABLE job_posting_skill_fact (
  job_id INT,
  skill_id INT,
  job_posted_date DATE,
  PRIMARY KEY (job_id, skill_id, job_posted_date)
);

-- Query: Python + SQL + remote-only postings by month
SELECT
  DATE_TRUNC('month', jpf.job_posted_date) AS posting_month,
  COUNT(DISTINCT jpf.job_id) AS job_count
FROM job_posting_skill_fact jpf
INNER JOIN job_dimension jd ON jpf.job_id = jd.job_id
INNER JOIN skill_dimension sd ON jpf.skill_id = sd.skill_id
WHERE sd.skill_name IN ('Python', 'SQL')
  AND jd.job_work_from_home = TRUE
GROUP BY DATE_TRUNC('month', jpf.job_posted_date)
ORDER BY posting_month DESC;
```

## Notes

- **Degenerate dimensions trap:** Date or location in a factless table are degenerate dimensions—they're not worth a separate dimension table, but they anchor the event. Don't over-normalize; a posting_date in the fact table is acceptable.
- **Grain clarity is critical:** Document whether one row = one job–skill pair or one job–skill–date combination. Ambiguous grain causes duplicate-count bugs that are invisible until stakeholders notice numbers don't match.
- **Indexing pays off:** Factless tables are join-heavy; index on (dimension_id, date) pairs heavily. Query plans will either fly or crawl depending on statistics and index design.
- **Bridging tables and type-2 dimensions:** A factless table is often a bridge table (many-to-many resolution). If dimensions have slow-changing attributes (e.g., "Python" renamed to "Python 3"), use type-2 SCD logic or snapshot the skill name directly in the fact table to avoid ambiguous history.
- **Revisit: conformed dimensions and bus matrix:** Factless tables force you to nail dimension conformation early—job_id must mean the same thing everywhere. Use a bus matrix to plan which facts and dimensions share keys.
