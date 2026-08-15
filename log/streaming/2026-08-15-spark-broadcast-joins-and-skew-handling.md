---
date: 2026-08-15
phase: streaming
topic: Spark: broadcast joins and skew handling
---

# Spark: broadcast joins and skew handling

*Streaming and distributed processing*

## Concept

A **broadcast join** sends a smaller table to all executors in the cluster, avoiding expensive shuffle operations when joining a large table with a small dimension table. Instead of partitioning both tables by join key and shuffling across the network, Spark replicates the small table in memory on each executor, then performs local lookups. This is critical in streaming contexts because the cost of shuffles compounds across micro-batches—repeated shuffles degrade end-to-end latency.

**Skew handling** addresses the case where one join key appears far more frequently than others, causing some partitions to balloon in size while others remain small. Without mitigation, a single executor processing the skewed key becomes a bottleneck (straggler problem), blocking the entire stage. In streaming, this manifests as inconsistent micro-batch latencies: some batches complete quickly, others hang waiting for the skewed partition to finish.

Broadcast joins work well when the small table fits in executor memory (typically <100 MB–2 GB depending on your cluster). For skewed joins of two large tables, you must redistribute the skewed keys across multiple partitions using salting or adaptive skew handling (Spark 3.2+). Without these techniques, a single hot key can dominate query time and cause cascading delays in your streaming pipeline.

## Practice

**Problem:** You are joining `job_postings_fact` (100 GB, streaming incrementally) with a slowly-changing `companies_dim` (500 MB) to enrich job titles with company industry classification. The join key is `company_id`. Most jobs post from a few mega-employers (e.g., Amazon, Microsoft), creating severe skew. Naive shuffle-based joins cause micro-batch latencies to spike unpredictably.

```sql
-- Broadcast the small company dimension to all executors
SELECT 
    jp.job_id,
    jp.job_title_short,
    jp.salary_year_avg,
    cd.company_industry,
    jp.job_posted_date
FROM job_postings_fact jp
BROADCAST(companies_dim cd)
  ON jp.company_id = cd.company_id
WHERE jp.job_posted_date >= current_date() - interval '1 day';

-- For skewed joins on both large tables, salt the hot key:
-- Split mega-employer (company_id = 1) across 10 sub-partitions
WITH salted_postings AS (
  SELECT job_id, job_title_short, company_id, 
         CASE WHEN company_id = 1 THEN CONCAT('1_', CAST(rand() * 10 AS INT))
              ELSE company_id END AS company_id_salted
  FROM job_postings_fact
),
salted_companies AS (
  SELECT company_id, company_industry,
         EXPLODE(SEQUENCE(0, 9)) AS salt_num,
         CONCAT('1_', salt_num) AS company_id_salted
  FROM companies_dim
  WHERE company_id = 1
  UNION ALL
  SELECT company_id, company_industry, 0, company_id
  FROM companies_dim
  WHERE company_id != 1
)
SELECT sp.job_id, sp.job_title_short, sc.company_industry
FROM salted_postings sp
JOIN salted_companies sc
  ON sp.company_id_salted = sc.company_id_salted;
```

## Notes

- **Broadcast size limits:** Check `spark.sql.broadcastTimeout` and executor memory; if the small table exceeds memory, broadcast will fail silently or spill, negating the benefit. Monitor with `spark.sql.autoBroadcastJoinThreshold` (default 10 MB in Spark 3.x).
- **Skew detection:** Use `EXPLAIN` and examine partition sizes in the Spark UI. If a few partitions are 10× larger than others, skew is present. Adaptive Query Execution (AQE, Spark 3.2+) can automatically skew-join, but tuning `spark.sql.adaptive.skewJoin.enabled` and `spark.sql.adaptive.skewJoin.skewFactor` is essential for streaming.
- **Streaming context:** Broadcast joins are most stable in streaming because the small table (dimension) rarely changes; reshuffle it only when it updates. Use `broadcastOf()` in Spark Structured Streaming to force broadcast.
- **Adjacent topics:** Connects to partitioning strategy, bucketing, and adaptive query execution. Revisit when implementing slowly-changing dimensions (SCD Type 2) or late-arriving fact data.
- **Common mistake:** Broadcasting both tables or broadcasting the large table. Recompute small table size after filters; a "small" table in raw form may be tiny after aggregation.
