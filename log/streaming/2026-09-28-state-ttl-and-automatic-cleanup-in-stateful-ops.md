---
date: 2026-09-28
phase: streaming
topic: State TTL and automatic cleanup in stateful ops
---

# State TTL and automatic cleanup in stateful ops

*Streaming and distributed processing*

## Concept

State TTL (time-to-live) is a mechanism in stateful streaming operations that automatically evicts old state entries after they haven't been accessed or updated for a specified duration. Without TTL, state grows unbounded—every unique key ever seen accumulates in memory or state backend, eventually causing out-of-memory errors, performance degradation, and cost bloat. This is critical in streaming because data arrives continuously and late arrivals are common; you need a principled way to forget old keys rather than keeping them forever.

TTL becomes essential when state cardinality is high or unknown. Examples: user session IDs, order correlations across multiple events, or deduplication windows. If a user never returns after 30 days, their session state should be purged. Without TTL, sessions from year one still occupy memory in year three. The automatic cleanup runs during state access or periodically, depending on backend configuration (RocksDB, in-memory, etc.).

## Practice

**Problem:** Track job posting deduplication across a 7-day sliding window. A duplicate post from the same job_id should be filtered if it arrives within 7 days of the first posting. However, job_id state should not accumulate forever—old job posts should be forgotten after 14 days of inactivity.

```sql
-- Flink SQL (or equivalent Kafka Streams/Spark Structured Streaming syntax)
CREATE TABLE job_postings_deduplicated AS
SELECT
    job_id,
    job_title_short,
    salary_year_avg,
    job_work_from_home,
    job_posted_date,
    job_location,
    ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY job_posted_date ASC) as post_rank
FROM job_postings_fact
WHERE post_rank = 1;

-- State TTL configuration (Flink)
CREATE TEMPORARY VIEW job_dedup_with_ttl AS
SELECT * FROM job_postings_deduplicated
WHERE CURRENT_TIMESTAMP - job_posted_date <= INTERVAL '7' DAY;

-- Backend setting (flink-conf.yaml or code)
-- state.backend.rocksdb.ttl.compaction.filter.enabled: true
-- state.backend.rocksdb.ttl.compaction.filter.deletion-time.to-live: 1209600000  -- 14 days in ms
```

## Notes

- **TTL vs. windowing:** TTL cleans up keyed state from stateful operators; windowing defines when to emit results. Use both: window to aggregate, TTL to prevent state explosion.
- **Backend matters:** In-memory state backends don't compact well; RocksDB with compaction filters is better for TTL enforcement. Always verify your backend supports incremental cleanup.
- **Late data and TTL tension:** Long TTLs protect against very late arrivals but increase memory cost. Tune TTL based on SLA for late events, not just on intuition.
- **Common mistake:** Setting TTL only on access (lazy cleanup) means state still grows until first access post-TTL; prefer background compaction for consistent resource usage.
- **Related topics:** State backend selection, watermarks and allowed lateness, exactly-once semantics (TTL cleanup must be idempotent), and monitoring state size metrics.
