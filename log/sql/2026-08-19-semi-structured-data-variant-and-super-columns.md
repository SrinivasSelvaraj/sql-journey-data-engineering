---
date: 2026-08-19
phase: sql
topic: Semi-structured data: VARIANT and SUPER columns
---

# Semi-structured data: VARIANT and SUPER columns

*SQL for analytics and engineering*

## Concept

VARIANT and SUPER are semi-structured data types that store JSON-like objects without enforcing schema at write time. VARIANT (Snowflake) and SUPER (Redshift Spectrum) let you nest arrays, objects, and mixed types in a single column, deferring parsing and validation until query time. This is powerful when upstream schemas evolve unpredictably—you can ingest API responses or log events without schema migrations—but it trades schema safety and query optimization for flexibility.

The critical trade-off: semi-structured columns are slower to scan and filter than native columns because the engine must deserialize and traverse the data at runtime. Without proper indexing strategies (materialized views, extracted columns) or query pruning, queries become expensive. You must explicitly extract and cast values using path operators (`.` notation in Snowflake, `FROM ... CROSS JOIN LATERAL ...` in Redshift), and null handling differs from standard SQL—missing paths return SQL NULL, not errors.

When to use: ingesting uncontrolled external data (webhooks, third-party APIs, logs). When *not* to use: if you know the schema in advance or need to filter/join frequently on nested fields—extract to columnar form instead.

## Practice

**Problem:** Job postings arrive as JSON in a raw table. You need to extract the hiring company name and benefits array from a nested `metadata` VARIANT column, then count how many postings mention "remote" in their benefits, grouped by company. Schema: `raw_job_postings(job_id, metadata VARIANT)` where metadata has structure `{"company": "TechCorp", "benefits": ["remote", "401k", "health"]}`.

```sql
-- Extract nested fields and explode benefits array
WITH parsed AS (
  SELECT
    job_id,
    metadata:'company'::STRING AS company_name,
    LATERAL FLATTEN(input => metadata:'benefits') AS benefit
  FROM raw_job_postings
)
SELECT
  company_name,
  COUNT(DISTINCT job_id) AS postings_with_remote
FROM parsed
WHERE benefit.value::STRING = 'remote'
GROUP BY company_name
ORDER BY postings_with_remote DESC;
```

## Notes

- **LATERAL FLATTEN is essential** for unnesting arrays within VARIANT; without it, you can't filter on array elements efficiently. Redshift uses `CROSS JOIN LATERAL json_each_text(…)` instead.
- **Cast early and often:** `metadata:'field'::STRING` forces type resolution at extraction time, enabling better optimization than leaving it as VARIANT throughout the query.
- **Materialized views + extracted columns:** For frequently accessed nested paths, create a view or ETL step that extracts them into native columns; this avoids repeated parsing and enables indexing.
- **NULL handling differs:** Missing paths in VARIANT return SQL NULL (not JSON null), so `WHERE metadata:'missing_field' IS NULL` works but behaves subtly—consider using `TRY_PARSE_JSON()` or conditional logic.
- **Adjacent topics:** schema inference (AUTO_DETECT, infer_schema functions), dynamic typing vs. static typing trade-offs, and incremental schema evolution patterns (e.g., tracking field lineage in metadata catalogs).
