---
date: 2026-10-31
phase: cloud
topic: Encryption at rest and in transit overhead
---

# Encryption at rest and in transit overhead

*Cloud platforms and storage*

## Concept

Encryption at rest protects data stored in databases, data lakes, or object storage; encryption in transit protects data moving over networks. Both add CPU overhead—encryption requires compute cycles, and decryption happens on read or at the database layer. In cloud platforms, this overhead is usually small (1–5% latency impact) but becomes visible under high throughput or when scanning large datasets repeatedly. You pay for it indirectly: slower queries mean longer-running jobs consume more compute credits, and some cloud providers charge separately for encryption key management (AWS KMS, Google Cloud KMS).

Without encryption at rest, compromised storage infrastructure exposes raw data. Without encryption in transit, network sniffing can intercept credentials, API keys, or sensitive fields mid-flight. However, unnecessary encryption of non-sensitive data or misconfigured key rotation wastes resources. The balance lies in encrypting what matters (PII, credentials, financial data) while understanding which tables or columns don't need it.

Query slowness tied to encryption often appears as elevated CPU usage during table scans rather than I/O wait. In Snowflake or BigQuery, enabling column-level encryption can push predicate filtering to the encrypted layer, forcing full decryption before filtering—defeating query optimization. Recognizing this pattern helps you decide whether to encrypt at the application layer instead.

## Practice

**Problem:** Your `job_postings_fact` table contains salary and location data. A nightly aggregation query that groups by `job_location` and averages `salary_year_avg` has slowed by 30% after your DBA enabled transparent data encryption (TDE) on the table. You need to identify if encryption is the culprit and optimize.

```sql
-- Before optimization: full table scan with decryption overhead
SELECT 
  job_location,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY
GROUP BY job_location
ORDER BY avg_salary DESC;

-- After optimization: materialize decrypted aggregates daily
-- (Move encryption boundary; pre-aggregate unencrypted intermediate results)
CREATE TEMPORARY TABLE job_postings_decrypted AS
SELECT 
  job_location,
  salary_year_avg,
  job_posted_date
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 30 DAY;

SELECT 
  job_location,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary
FROM job_postings_decrypted
GROUP BY job_location
ORDER BY avg_salary DESC;

-- Or: use encrypted materialized view + clustering on job_location
CREATE MATERIALIZED VIEW job_postings_agg_mv
CLUSTER BY job_location AS
SELECT 
  job_location,
  salary_year_avg
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 90 DAY;
```

## Notes

- **Column vs. table encryption:** Encrypting only `salary_year_avg` and `job_location` is cheaper than whole-table encryption if most columns are non-sensitive; test push-down filtering behavior with your platform.
- **Key rotation costs:** AWS KMS charges ~$0.03 per 10k requests; if your queries decrypt millions of rows hourly, key access becomes a line item—batch decryption or cached keys reduce cost.
- **In-transit encryption overhead:** TLS 1.3 is cheap (<2% overhead on modern CPUs), but self-signed or outdated cipher suites can spike to 10%+; verify your cloud provider's default cipher suite.
- **Application vs. database encryption:** Encrypting sensitive fields at the application layer (before insert) keeps the database unaware and avoids query-layer slowness, but complicates indexing and filtering—trade-off depends on access patterns.
- **Adjacent concepts:** compression (often applied together; encryption prevents compression gains), column-store formats (Parquet + encryption interaction), and audit logging (encrypted data makes compliance audits slower if logs aren't structured carefully).
