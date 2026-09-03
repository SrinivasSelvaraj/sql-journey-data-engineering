---
date: 2026-09-03
phase: cloud
topic: Redshift: spectrum for querying S3, RA3 nodes for flexibility
---

# Redshift: spectrum for querying S3, RA3 nodes for flexibility

*Cloud platforms and storage*

## Concept

**Redshift Spectrum** extends Redshift's query engine to S3 without moving data—you define external tables pointing to parquet, CSV, or ORC files in S3 and query them alongside native Redshift tables. This matters when your data lake lives in S3 but you want SQL joins across hot (Redshift) and cold (S3) data without ETL overhead. The cost model shifts: you pay for Redshift compute scanning S3 data (not S3 API calls), so pushing large unfiltered scans to external tables kills your budget.

**RA3 nodes** (dc2.large, ra3.4xlplus) add managed storage decoupled from compute, with automatic caching of frequently-accessed S3 data. Without RA3, you're locked into dense compute nodes where storage and CPU scale together; RA3 lets you scale query workers independently and avoids re-scanning identical S3 files repeatedly. Combined with Spectrum, RA3 acts as a persistent cache between S3 and active queries, dramatically reducing per-query scan costs on repeated access patterns.

Without understanding Spectrum's cost model, you'll write queries that scan terabytes of raw S3 data per execution and see surprise bills. Without RA3's caching, you'll re-scan the same S3 partition five times in an hour and wonder why the cluster is slow—the bottleneck is S3 I/O, not Redshift CPU.

## Practice

**Problem:** You query `job_postings_fact` which lives partly in Redshift (recent 3 months, 10GB) and partly archived in S3 (older 2 years, 500GB parquet files partitioned by `job_posted_date`). You need salary statistics for all postings, but filtering in the `WHERE` clause doesn't eliminate the full S3 scan, costing $50+ per query.

```sql
-- Create external schema pointing to S3
CREATE EXTERNAL SCHEMA spectrum_jobs FROM DATA CATALOG
DATABASE 'job_postings_db'
IAM_ROLE 'arn:aws:iam::ACCOUNT:role/redshift-spectrum-role';

-- Define external table with partition pruning
CREATE EXTERNAL TABLE spectrum_jobs.job_postings_archive (
  job_id INT,
  job_title_short VARCHAR(50),
  salary_year_avg INT,
  job_work_from_home BOOLEAN,
  job_posted_date DATE,
  job_location VARCHAR(255)
)
PARTITIONED BY (year INT, month INT)
STORED AS PARQUET
LOCATION 's3://my-bucket/job_postings_archive/'
TABLE PROPERTIES ('classification' = 'parquet');

-- Query with partition elimination: only scans matching year/month folders
SELECT 
  job_title_short,
  AVG(salary_year_avg) as avg_salary,
  COUNT(*) as posting_count
FROM spectrum_jobs.job_postings_archive
WHERE year = 2022 AND month IN (1, 2, 3)  -- Pushes down partition filter to S3
GROUP BY job_title_short
ORDER BY avg_salary DESC;
```

## Notes

- **Partition pruning is mandatory**: without explicit partition columns in your `WHERE` clause, Spectrum scans every file in the S3 location. Always structure S3 data hierarchically (year/month/day) and reference those columns early in filtering.

- **RA3 caching requires repeated queries**: if you query different date ranges every time, caching won't help; RA3 shines on dashboards or reporting jobs that hit the same S3 ranges daily. Monitor `SYS_QUERY_DETAIL.spectrum_scanned_bytes` to spot patterns.

- **Redshift Advisor vs. query plan**: slow Spectrum queries rarely show CPU bottlenecks; check CloudWatch for `SpectrumScan` duration and S3 request metrics. A slow query may be I/O-bound on S3, not CPU-bound on Redshift.

- **Adjacent: data lake design and columnar format**. Parquet and ORC compression matter enormously—uncompressed CSV in S3 costs 10× more to scan. Pair Spectrum with tools like AWS Glue or dbt to keep S3 data organized and stats fresh.

- **Revisit cost estimation**: use `EXPLAIN` to see estimated scanned bytes, then multiply by $5/TB to forecast Spectrum query cost. A 100GB unfiltered scan = ~$0.50 per execution—scales quickly in production.
