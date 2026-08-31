---
date: 2026-08-31
phase: modelling
topic: UUID choice: v4 randomness vs v7 sortability
---

# UUID choice: v4 randomness vs v7 sortability

*Data modelling and warehousing*

## Concept

UUID v4 generates random identifiers with no inherent order, making it impossible to infer timing or sequence from the ID itself. UUID v7, standardized more recently, embeds a Unix timestamp in the first 48 bits, creating sortable IDs that increase monotonically over time. In data warehousing, this distinction affects query performance, index efficiency, and downstream analytics. When you insert rows with v4 UUIDs into a clustered primary key, the database scatters writes across the entire index structure, causing page splits and fragmentation. With v7, sequential inserts land on hot pages, reducing I/O and lock contention. For analytics, v7 UUIDs let you infer recency directly from the ID—useful for time-series partitioning, incremental loads, and debugging data freshness without joining to a timestamp column.

The choice breaks down when you need both anonymity and sortability. v4 is safer if you expose IDs publicly (job posting URLs, API responses) because no one can guess the next ID or infer creation patterns. v7 sacrifices some privacy—an observer seeing sequential IDs knows roughly when records were created. Additionally, v7 adoption is newer; older databases and frameworks may not support it natively, requiring custom generation logic that introduces bugs or inconsistency across services.

## Practice

**Problem:** You're building `job_postings_fact` and need to partition historical data by job creation date for faster queries. Engineers frequently filter on `job_posted_date`, but that column is sometimes NULL during ETL. When it is NULL, you can't reliably assign partitions. Using v4 UUIDs as `job_id`, you have no fallback. Using v7, you can extract the embedded timestamp as a surrogate if the date is missing.

```sql
-- Schema using UUID v7
CREATE TABLE job_postings_fact (
    job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),  -- v7 in PostgreSQL 13+
    job_title_short VARCHAR(100) NOT NULL,
    salary_year_avg DECIMAL(10, 2),
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR(100),
    _partition_year INT GENERATED ALWAYS AS (
        COALESCE(EXTRACT(YEAR FROM job_posted_date)::INT,
                 EXTRACT(YEAR FROM to_timestamp((get_byte(job_id, 0)::bigint << 40 | get_byte(job_id, 1)::bigint << 32) / 1000.0)))::INT
    ) STORED
) PARTITION BY RANGE (_partition_year);

-- Incremental load: v7 IDs naturally sort, so you can resume from last max(job_id)
INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
SELECT 
    gen_random_uuid(),  -- v7 monotonic within millisecond precision
    title, salary, remote, posted_at, location
FROM external_job_feed
WHERE job_id > (SELECT COALESCE(MAX(job_id), '00000000-0000-0000-0000-000000000000') FROM job_postings_fact)
ORDER BY job_id;
```

## Notes

- **Index fragmentation under v4 is real**: random inserts cause B-tree page splits; v7 reduces this by 60–80% in high-volume systems. Measure with `EXPLAIN ANALYZE` on large tables.
- **Timestamp extraction from v7 is database-specific**: PostgreSQL uses bit manipulation; MySQL's `UUID_TO_BIN` and `BIN_TO_UUID` handle it differently. Document your approach in schema comments.
- **Don't assume v7 is universally safe**: older frameworks (Django ORM, some ORMs) may still default to v4. Explicitly set generation at the application or database layer, not both.
- **v7 + distributed systems require clock synchronization**: if multiple services generate UUIDs across regions, clock skew can break monotonicity. Centralize generation or use logical clocks if sorting across services matters.
- **Relates to partitioning strategy, time-series fact tables, and incremental load patterns**: once you commit to v7, your ETL, recovery procedures, and schema documentation all depend on that choice. Revisit during schema review with the full team.
