---
date: 2026-09-10
phase: reliability
topic: Duplicate detection: exact match vs fuzzy matching
---

# Duplicate detection: exact match vs fuzzy matching

*Quality, reliability and the professional layer*

## Concept

Exact match duplicate detection compares records field-for-field and flags only identical values; fuzzy matching uses similarity algorithms (Levenshtein distance, Jaro-Winkler, cosine similarity) to catch near-duplicates with typos, formatting differences, or encoding variations. Exact match is fast, deterministic, and auditable—you can explain precisely why two records matched. Fuzzy matching is necessary when source data is messy: job titles like "Senior Software Engineer" vs "Sr. Software Engr." are functionally identical but won't match exactly.

Without duplicate detection, fact tables inflate with redundant records, breaking aggregations and costing storage. A job posting scraped twice from different sources might have the same job_id but slightly different location formatting ("San Francisco, CA" vs "San Francisco CA"). Exact match would miss this; you'd report the same role twice, inflating open positions by 50%. Fuzzy matching catches it, but at computational cost and with a risk of false positives if your threshold is too loose.

The professional distinction: exact match works when your ETL controls the source (internal systems, clean APIs). Fuzzy matching is required when you own data quality in hostile environments—web scraping, user-submitted forms, multiple vendor feeds. Choosing wrong means your reports are either wrong (missed duplicates) or your pipeline is unmaintainably slow (over-fuzzy-matching on large tables).

## Practice

**Problem**: You ingest job postings from two vendor feeds daily. Both may list the same role (same company, same location, same posting date) but with different job titles: one says "Data Analyst" and another says "Data Analyst - Healthcare." An exact match on job_title_short will miss this duplicate. Your fact table is inflating, and you're overcounting open positions.

```sql
-- Exact match: catches only identical titles
SELECT 
  COALESCE(a.job_id, b.job_id) AS job_id,
  a.job_title_short,
  a.job_location,
  COUNT(*) AS count
FROM job_postings_fact a
FULL OUTER JOIN job_postings_fact b
  ON a.job_title_short = b.job_title_short
  AND a.job_location = b.job_location
  AND a.job_posted_date = b.job_posted_date
  AND a.job_id != b.job_id
GROUP BY 1, 2, 3
HAVING COUNT(*) > 1;

-- Fuzzy match: catches near-duplicates using trigram similarity (PostgreSQL)
SELECT 
  a.job_id,
  b.job_id,
  a.job_title_short,
  b.job_title_short,
  SIMILARITY(a.job_title_short, b.job_title_short) AS similarity_score
FROM job_postings_fact a
JOIN job_postings_fact b
  ON a.job_location = b.job_location
  AND a.job_posted_date = b.job_posted_date
  AND a.job_id < b.job_id
WHERE SIMILARITY(a.job_title_short, b.job_title_short) > 0.7
ORDER BY similarity_score DESC;
```

The fuzzy query requires `pg_trgm` extension and catches "Data Analyst" vs "Data Analyst - Healthcare" (similarity ~0.82). Use a threshold (0.7–0.85) calibrated against manual review of false positives.

## Notes

- **Threshold tuning is mandatory**: A 0.9 threshold catches only typos; 0.6 creates false positives (matching "Analyst" to "Accountant"). Build a validation dataset of 50–100 known duplicates and non-duplicates to calibrate.
- **Exact match first, then fuzzy**: Always deduplicate on stable keys (job_id + source) exactly before attempting fuzzy matching on text. Fuzzy matching on a pre-deduplicated set is faster and produces fewer false positives.
- **Composite keys prevent many problems**: If you can add (vendor_id, vendor_job_id) as a natural key before fuzzy matching, do it—you've eliminated cross-vendor duplicates exactly and only need fuzzy matching within vendors.
- **Connects to data lineage and idempotency**: A deduplication step must be repeatable—running it twice should produce identical results. Store deduplication rules and threshold versions in metadata so you can audit why a record was flagged.
- **Cost trap at scale**: Fuzzy matching on a 10M-row table with nested joins is O(n²). Use bucketing (location + posting date) or LSH (locality-sensitive hashing) to reduce candidate pairs before computing similarity.
