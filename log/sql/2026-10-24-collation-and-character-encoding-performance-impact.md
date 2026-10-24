---
date: 2026-10-24
phase: sql
topic: Collation and character encoding performance impact
---

# Collation and character encoding performance impact

*SQL for analytics and engineering*

## Concept

Collation determines how strings are compared and sorted in SQL queries—it affects equality checks, joins, filtering, and ORDER BY operations. Character encoding (UTF-8, ASCII, etc.) determines how many bytes each character consumes; mismatches between column encoding and query encoding force implicit conversions, causing full table scans instead of index usage. Performance breaks when:
- A WHERE clause compares columns with different collations (`job_title_short COLLATE utf8mb4_unicode_ci = 'Data Engineer' COLLATE utf8mb4_bin`), disabling index usage.
- Case-insensitive collation is applied to a large text column; filtering becomes slower because the database cannot use a binary-safe index range.
- Character encoding conversion happens mid-query (e.g., joining UTF-8 and Latin1 columns), forcing the optimizer to materialize intermediate results.

The practical rule: **align collation and encoding across columns being compared; choose case-sensitive collations for exact-match lookups on indexed columns; use case-insensitive only when semantically required (e.g., email addresses).**

## Practice

**Problem:** You're filtering `job_postings_fact` by job title and location. The `job_title_short` column uses `utf8mb4_unicode_ci` (case-insensitive), but your WHERE clause should perform case-sensitive matching on exact titles for speed. The `job_location` column is sometimes NULL or has leading/trailing spaces. Write a query that efficiently finds all "Data Engineer" roles in "New York, NY" with salary > 100,000.

```sql
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location
FROM job_postings_fact
WHERE job_title_short = 'Data Engineer' COLLATE utf8mb4_general_ci
  AND TRIM(job_location) = 'New York, NY'
  AND salary_year_avg > 100000
ORDER BY job_posted_date DESC;
```

*Better approach (if you control schema):* recreate `job_title_short` as `utf8mb4_general_ci` for case-insensitive semantics and add a computed index on `TRIM(job_location)` to handle whitespace efficiently. If using MySQL 8.0+:

```sql
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_location
FROM job_postings_fact
WHERE job_title_short = 'Data Engineer'  -- relies on column default collation
  AND TRIM(job_location) = 'New York, NY'
  AND salary_year_avg > 100000
ORDER BY job_posted_date DESC;
```

## Notes

- **Collation mismatch silently disables indexes:** A WHERE clause comparing differently collated columns forces a table scan. Always check `SHOW CREATE TABLE` and `EXPLAIN` output for "Using where" without "Using index".
- **TRIM and function wrapping:** `TRIM(job_location) = 'New York, NY'` prevents index usage on `job_location`. Use generated columns or pre-clean data at ingestion if this is a frequent query pattern.
- **UTF-8 vs UTF8MB4:** MySQL's `utf8` is actually 3-byte; use `utf8mb4` (4-byte) for emoji and modern Unicode support. Encoding mismatch between client and server (`SET NAMES utf8mb4`) can cause character corruption and unexpected filter results.
- **Case sensitivity trade-off:** `utf8mb4_bin` is fastest but case-sensitive; `utf8mb4_unicode_ci` supports case-insensitive and accent-insensitive comparisons but is slower. Profile your actual queries; sometimes a secondary case-insensitive column or application-level filtering is better.
- **Adjacent topics:** indexing strategy (when indexes are usable), query plan analysis (EXPLAIN), data normalization (cleaning at load time rather than query time), and connection charset negotiation for multi-region systems.
