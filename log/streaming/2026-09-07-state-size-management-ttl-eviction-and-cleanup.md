---
date: 2026-09-07
phase: streaming
topic: State size management: TTL, eviction and cleanup
---

# State size management: TTL, eviction and cleanup

*Streaming and distributed processing*

## Concept

State size management is the practice of controlling how much data a streaming application holds in memory or persistent state stores at any given time. In stateful stream processing (joins, aggregations, deduplication), unbounded state grows indefinitely as new records arrive, eventually exhausting memory and degrading performance. Time-to-live (TTL) policies automatically expire old state entries, eviction strategies remove least-recently or least-frequently used entries when size thresholds are exceeded, and explicit cleanup jobs purge stale data from backing stores.

Without state management, a simple stream join over job postings and applicant histories will accumulate years of old postings in state, consuming gigabytes while the processing engine slows down trying to manage objects that will never match again. Late-arriving data compounds the problem: a posting from six months ago should not cause a re-hash of the entire state store. TTL and eviction ensure that only "hot" state—data likely to be needed for future matches—remains accessible.

State management directly impacts latency, throughput, and cost. A well-tuned TTL prevents memory bloat, allows garbage collection to run efficiently, and keeps operator processing time predictable. Poor state management is a common hidden cost in production streaming systems, manifesting as mysterious out-of-memory crashes or gradual performance degradation that is hard to diagnose.

## Practice

**Problem:** You're building a real-time job posting deduplication system. Job postings arrive continuously, but duplicates may appear days or weeks later from different job boards. You want to deduplicate within a 30-day window, then forget old postings to avoid state explosion. How do you structure state retention?

```sql
-- Pseudo-code for stateful deduplication with TTL (Flink-style)

SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  ROW_NUMBER() OVER (
    PARTITION BY job_id 
    ORDER BY job_posted_date DESC
  ) AS dedup_rank

FROM job_postings_fact

-- State retention: keep only records within 30 days of the latest posting
QUALIFY 
  job_posted_date >= DATE_SUB(MAX(job_posted_date) OVER (PARTITION BY job_id), INTERVAL 30 DAY)
  AND dedup_rank = 1

-- TTL configuration (framework-level):
-- RocksDB TTL: 30 days
-- Eviction policy: LRU (least recently used) if state exceeds 2GB
-- Cleanup interval: run every 5 minutes
```

Alternatively, in an event-time windowed context, use session windows with a 30-day gap timeout, which automatically expires state when no matching records arrive within the window.

## Notes

- **Mistake:** Setting TTL too short loses legitimate late data; setting it too long defeats the purpose. Validate TTL against your SLA for late arrivals and upstream delay percentiles (p95, p99).
- **Mistake:** Confusing eviction (size-based removal) with TTL (time-based removal). Use TTL for semantically meaningful windows (e.g., "join within 30 days"), and eviction as a safety valve when state still exceeds memory budgets.
- **Connection:** State management ties directly to watermarking and allowed lateness in event-time processing; they must be aligned or you'll evict data before the watermark catches up.
- **Revisit:** Monitor state size and backend store metrics (RocksDB compaction, checkpoint size) to detect when TTL is insufficient or eviction is too aggressive.
- **Checkpoint and recovery:** Expired state should not be serialized into checkpoints. Configure your streaming framework to prune expired state before snapshots to minimize recovery time.
