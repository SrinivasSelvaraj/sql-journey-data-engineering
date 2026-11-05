---
date: 2026-11-05
phase: sql
topic: String collation, encoding and international character set issues
---

# String collation, encoding and international character set issues

*SQL for analytics and engineering*

## Concept

Collation determines how strings are compared, sorted, and matched in SQL queries. It defines rules for character ordering (e.g., case-sensitivity, accent-sensitivity, language-specific sort order) and encoding specifies how characters are stored in bytes (UTF-8, UTF-16, ASCII, etc.). Without explicit attention to these, queries fail silently: case-sensitive collations cause `WHERE job_title = 'Data Analyst'` to miss `'data analyst'` records; accent-sensitive collations treat `'café'` differently from `'cafe'`; encoding mismatches corrupt international characters and break WHERE/JOIN logic.

These issues matter most when: (1) filtering or joining on text columns with user input or data from multiple sources, (2) sorting results for reports where order must be predictable across regions, (3) working with non-ASCII characters (names, locations in non-English languages), and (4) integrating data from legacy systems or APIs with different encoding defaults.

The practical consequence is query correctness: a case-sensitive collation paired with inconsistent data entry means aggregate functions count duplicates, filters miss rows, and JOINs fail to match valid records. In analytics and interviews, demonstrating awareness shows you can debug mysterious data gaps and write queries that scale beyond English-only datasets.

## Practice

**Problem:** Your `job_postings_fact` table contains job locations like `'New York'`, `'new york'`, `'NEW YORK'` entered by different users. A query counting jobs per location is overcounting and your JOIN to a location dimension table fails to match 30% of records. Write a query that correctly groups and counts jobs by location, and explain how collation impacts the result.

```sql
-- Without collation handling (WRONG - may overcount or miss matches)
SELECT job_location, COUNT(*) as job_count
FROM job_postings_fact
GROUP BY job_location
ORDER BY job_location;

-- With collation handling (CORRECT)
SELECT LOWER(job_location) AS job_location_normalized, COUNT(*) as job_count
FROM job_postings_fact
WHERE job_location IS NOT NULL
GROUP BY LOWER(job_location)
ORDER BY job_location_normalized;

-- Or, using explicit collation (database-specific)
-- PostgreSQL example:
SELECT job_location COLLATE "C" AS job_location, COUNT(*) as job_count
FROM job_postings_fact
WHERE job_location IS NOT NULL
GROUP BY job_location COLLATE "C"
ORDER BY job_location COLLATE "C";

-- For JOIN scenario with dimension table
SELECT d.location_id, d.location_name, COUNT(j.job_id) as job_count
FROM location_dimension d
LEFT JOIN job_postings_fact j 
  ON LOWER(d.location_name) = LOWER(j.job_location)
GROUP BY d.location_id, d.location_name
ORDER BY job_count DESC;
```

## Notes

- **Normalization before comparison:** Always `LOWER()` or `UPPER()` strings for matching unless case-sensitivity is a business requirement; pair with `TRIM()` for whitespace.
- **Collation vs. encoding confusion:** Encoding (UTF-8) specifies storage format; collation (utf8_general_ci, utf8_bin) specifies comparison rules. You need both correct. In interviews, mention this distinction to show depth.
- **JOINs and GROUP BY are silent failures:** Unlike WHERE clauses, mismatched collation in JOINs produces no error—just incomplete results. Always test with `COUNT(DISTINCT)` to spot anomalies.
- **Database defaults vary:** MySQL defaults to `utf8mb4_unicode_ci` (case-insensitive), PostgreSQL uses `C` collation (binary), SQL Server has server-level defaults. Check your system; don't assume.
- **Adjacent topics:** Data quality/profiling (detecting case inconsistencies early), timezone handling (similar invisible gotcha), and query plan analysis (collation can affect index selection and performance).
