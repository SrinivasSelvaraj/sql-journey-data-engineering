---
date: 2026-08-26
phase: sql
topic: String collation impact on sorting and joins
---

# String collation impact on sorting and joins

*SQL for analytics and engineering*

## Concept

String collation determines how character data is compared, sorted, and joined—it defines the rules for equality, ordering, and case sensitivity. Different collations (e.g., `utf8mb4_unicode_ci` vs. `utf8mb4_bin`) affect whether 'New York' matches 'new york', and whether 'é' sorts before or after 'e'. Without attention to collation, joins silently fail to match rows that *should* match, sort results appear scrambled to users, and index usage breaks because the optimizer can't use an index built under a different collation.

Collation mismatches between columns—especially across joins—force implicit conversions that disable index usage and degrade performance. A common failure: joining `users.email` (collation A) to `logs.user_email` (collation B) results in a table scan instead of index seek. Collation also affects `LIKE` patterns, `ORDER BY`, and `GROUP BY` cardinality; case-insensitive collations may group 'USA' and 'usa' as one value, while binary collations treat them as distinct.

## Practice

**Problem:** You're joining `job_postings_fact` to a `companies` table on `job_location`, but the join returns fewer rows than expected. The `companies.location` column is stored as `utf8mb4_bin` (case-sensitive, binary), while `job_postings_fact.job_location` defaults to `utf8mb4_unicode_ci` (case-insensitive). Rows like 'New York' in job_postings don't match 'new york' in companies.

```sql
-- Bad: collation mismatch causes missed matches
SELECT jp.job_id, c.company_name
FROM job_postings_fact jp
JOIN companies c ON jp.job_location = c.location
WHERE jp.job_posted_date >= '2024-01-01';

-- Good: explicitly cast to matching collation
SELECT jp.job_id, c.company_name
FROM job_postings_fact jp
JOIN companies c 
  ON CAST(jp.job_location AS CHAR(100) COLLATE utf8mb4_unicode_ci) 
     = CAST(c.location AS CHAR(100) COLLATE utf8mb4_unicode_ci)
WHERE jp.job_posted_date >= '2024-01-01';

-- Better: standardize collation at schema design or normalize case in ETL
SELECT jp.job_id, c.company_name
FROM job_postings_fact jp
JOIN companies c ON LOWER(jp.job_location) = LOWER(c.location)
WHERE jp.job_posted_date >= '2024-01-01';
```

## Notes

- **Collation cascades:** If a table's default collation differs from a column's, joins involving that column may inherit the wrong collation. Always check `SHOW CREATE TABLE` and `INFORMATION_SCHEMA.COLUMNS` collation.
- **Index alignment:** Indexes are built under the collation active at creation time. A query using a different collation can't use that index; use `EXPLAIN` to confirm index hits, not table scans.
- **Case-sensitivity trade-off:** `utf8mb4_unicode_ci` is slower but more forgiving for user-facing joins (location, email); `utf8mb4_bin` is fast but demands exact case matching. Choose intentionally per column.
- **GROUP BY cardinality:** With case-insensitive collation, `GROUP BY job_location` may collapse 'Remote' and 'REMOTE' into one group. Test aggregation logic against real data to catch surprises.
- **Related:** Character sets (encoding), `COLLATE` clause in SELECT, implicit conversions, index selectivity, internationalization (Unicode normalization), and performance tuning via `SET SESSION collation_connection`.
