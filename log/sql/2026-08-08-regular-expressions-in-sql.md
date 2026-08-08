---
date: 2026-08-08
phase: sql
topic: Regular expressions in SQL
---

# Regular expressions in SQL

*SQL for analytics and engineering*

## Concept

Regular expressions (regex) in SQL allow pattern matching on text fields beyond simple equality or LIKE operators. Most SQL dialects support them via functions like `REGEXP_MATCH()` (PostgreSQL), `REGEXP_LIKE()` (Oracle, MySQL), or `~` operators, enabling you to extract, validate, or filter strings based on complex patterns. This matters in analytics when you need to parse messy data—extracting domain names from emails, validating phone formats, or grouping job titles by semantic patterns rather than exact strings.

Without regex, you're stuck chaining multiple LIKE conditions or substring operations, which becomes unmaintainable and slow. For example, finding all variations of "Data Engineer" (Data Engineer, Data Eng., Sr. Data Engineer, etc.) requires many OR clauses; regex solves it with a single pattern. The cost is readability if the pattern is obscure and slight performance overhead compared to indexed equality lookups, so it's a deliberate trade-off.

Most SQL systems don't index regex matches, meaning full table scans are common. For large datasets, push filtering to regex-supported WHERE clauses early, and consider denormalizing or pre-computing classifications if regex filtering becomes a bottleneck on repeated queries.

## Practice

**Problem:** From `job_postings_fact`, find all job titles that contain either "engineer" or "architect" (case-insensitive) and return the count by job title. Ensure you're matching whole words only (not "engineered" or "architecture").

```sql
SELECT 
  job_title_short,
  COUNT(*) as posting_count
FROM job_postings_fact
WHERE job_title_short ~* '\m(engineer|architect)\M'
  -- PostgreSQL syntax: ~* is case-insensitive regex match
  -- \m and \M are word boundaries
GROUP BY job_title_short
ORDER BY posting_count DESC;

-- Alternative for MySQL/MariaDB:
WHERE job_title_short REGEXP '\\b(engineer|architect)\\b'
  AND job_title_short NOT REGEXP '\\b(engineering|architecture)\\b';

-- Alternative for standard SQL (slower, but portable):
WHERE LOWER(job_title_short) LIKE '%engineer%'
   OR LOWER(job_title_short) LIKE '%architect%';
```

## Notes

- **Word boundaries matter:** `\b` or `\m/\M` prevent matching substrings; test your pattern on known data before production queries.
- **Dialect sprawl:** PostgreSQL (`~`), MySQL (`REGEXP`), Oracle (`REGEXP_LIKE()`), and Snowflake (`REGEXP`) all differ slightly—always check your platform's syntax and anchor your patterns carefully.
- **Performance trap:** Regex on unindexed columns forces full table scans; profile before deploying on 100M+ row tables; consider materializing a `job_category` column if you're repeatedly classifying by regex.
- **Adjacent skills:** This connects to data cleaning (combining regex with CASE/WHEN for ETL), string functions (`SUBSTRING`, `SPLIT_PART`), and understanding collation (case sensitivity rules).
- **Common mistake:** Forgetting to escape special regex characters (`.`, `*`, `+`, `?`, `[`, `]`) when they're literal; use `REGEXP_ESCAPE()` or manually escape if available.
