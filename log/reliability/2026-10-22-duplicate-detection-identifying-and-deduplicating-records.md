---
date: 2026-10-22
phase: reliability
topic: Duplicate detection: identifying and deduplicating records
---

# Duplicate detection: identifying and deduplicating records

*Quality, reliability and the professional layer*

## Concept

Duplicate detection identifies when the same logical record appears multiple times in a dataset, which corrupts analytics, inflates metrics, and breaks joins. Unlike primary key violations (which databases catch), duplicates emerge from real-world sources: ETL reruns that don't idempotently upsert, API pagination bugs that repeat records, or multiple upstream systems feeding the same table. They're invisible until you aggregate—a count of users becomes 15% inflated, a revenue sum double-counts transactions—and fixing them retroactively is expensive.

The professional approach treats deduplication as a design problem, not a cleanup problem. You establish a deduplication strategy *before* data lands in your table: decide whether to deduplicate at ingestion (preferred), enforce it via upsert logic keyed to a natural identifier, or quarantine duplicates in a staging layer for investigation. Without this, you're constantly running reconciliation queries and losing trust in your own numbers.

## Practice

**Problem:** Your `job_postings_fact` table is receiving duplicate rows from a daily API sync. The API sometimes reruns partially and repeats records from the last 3 days. You need to detect exact duplicates and keep only the most recent instance per job posting.

```sql
-- Detect duplicates and deduplicate
WITH ranked_postings AS (
  SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    ROW_NUMBER() OVER (
      PARTITION BY job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location
      ORDER BY job_posted_date DESC
    ) AS rn
  FROM job_postings_fact
)
DELETE FROM job_postings_fact
WHERE (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  IN (SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location 
      FROM ranked_postings WHERE rn > 1);

-- Or, rebuild the table idempotently:
CREATE TABLE job_postings_fact_deduped AS
SELECT DISTINCT ON (job_id) *
FROM job_postings_fact
ORDER BY job_id, job_posted_date DESC;
```

## Notes

- **Exact vs. fuzzy duplicates:** Exact duplicates (row-for-row identical) are caught by `DISTINCT`. Fuzzy duplicates (same job, slightly different title or location string) require fuzzy matching and domain knowledge—decide your tolerance upfront.

- **Natural key vs. surrogate key:** Always deduplicate on your *natural* key (job_id here), not a surrogate/UUID, otherwise you'll create new duplicates masquerading as unique records.

- **Idempotency at the source:** The real fix is making your ETL idempotent—upsert into a temp table, then merge only changed rows. Deduplication is a safety net, not the primary defense.

- **Audit trail:** Before deleting duplicates, log which records were removed, when, and why. You'll need this for reconciliation and trust-building with stakeholders.

- **Connects to:** data lineage (tracking duplicate origins), SLA monitoring (detecting upstream failures causing reruns), and fact table grain design (ensuring your grain is granular enough to avoid false duplicates).
