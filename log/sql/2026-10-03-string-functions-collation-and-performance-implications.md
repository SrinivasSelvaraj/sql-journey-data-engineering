---
date: 2026-10-03
phase: sql
topic: String functions: collation and performance implications
---

# String functions: collation and performance implications

*SQL for analytics and engineering*

## Concept

Collation determines how strings are compared, sorted, and matched in SQL queries. Different collations define rules for case sensitivity, accent sensitivity, and character ordering (e.g., UTF8_GENERAL_CI vs. UTF8_UNICODE_CI). When you filter or join on string columns without understanding the active collation, you may get unexpected matches (e.g., 'café' matching 'cafe'), or conversely, miss matches you expected. Collation also directly impacts index usage: a query that implicitly converts between collations may force a full table scan instead of using an index on that column.

The performance penalty occurs during string comparisons in WHERE, JOIN, and ORDER BY clauses. When columns have different collations, the database must apply conversion functions, which prevents index seek and triggers a scan. In analytics and engineering contexts, this is especially problematic on large fact tables where a single collation mismatch on a join key can turn a 100ms query into a 10-second query. Understanding your database's default collation and explicitly specifying COLLATE when needed ensures both correctness and plan efficiency.

## Practice

**Problem:** You are joining `job_postings_fact` with a `company_dim` table on company name. Job postings were ingested with UTF8_GENERAL_CI (case-insensitive), but the dimension table uses UTF8_UNICODE_CI (accent-sensitive). A query filtering for jobs in "São Paulo" returns no results, and the execution plan shows a table scan instead of an index seek on the location column.

```sql
-- INCORRECT: Implicit collation mismatch causes scan and missed matches
SELECT jp.job_id, jp.job_title_short
FROM job_postings_fact jp
WHERE jp.job_location = 'São Paulo';

-- CORRECT: Explicitly cast to consistent collation, enabling index seek
SELECT jp.job_id, jp.job_title_short
FROM job_postings_fact jp
WHERE jp.job_location COLLATE UTF8_UNICODE_CI = 'São Paulo' COLLATE UTF8_UNICODE_CI;

-- OR: Normalize at ingestion/schema level
-- ALTER TABLE job_postings_fact 
-- MODIFY job_location VARCHAR(255) COLLATE utf8mb4_unicode_ci;
-- Then the simple query works efficiently:
SELECT jp.job_id, jp.job_title_short
FROM job_postings_fact jp
WHERE jp.job_location = 'São Paulo';
```

## Notes

- **Index invalidation:** Adding COLLATE to a WHERE clause after an index is built on that column may bypass the index. Collation must match the index definition or you lose the seek benefit.
- **Join performance:** Always verify collation on join keys; a mismatch forces a nested loop with repeated conversions. Use `SHOW FULL COLUMNS FROM table_name` or `INFORMATION_SCHEMA.COLUMNS` to inspect actual collations.
- **Case-sensitivity trade-off:** UTF8_GENERAL_CI (case-insensitive) is faster for equality but loses precision; UTF8_UNICODE_CI is more correct for international text but slightly slower. Choose based on your domain (job titles may benefit from case-insensitive matching).
- **String normalization:** Consider normalizing strings at ETL time (uppercase, trim, remove accents) rather than at query time to avoid runtime COLLATE overhead entirely.
- **Related topics:** Character sets (UTF8 vs. ASCII), expression indexes, and cardinality estimation—all interact with collation choices and affect query planning.
