---
date: 2026-10-17
phase: streaming
topic: Kafka compacted topics: tombstones and log compaction
---

# Kafka compacted topics: tombstones and log compaction

*Streaming and distributed processing*

## Concept

Kafka **log compaction** is a retention policy that keeps only the latest value for each key in a topic, deleting older versions of the same key. This is essential for topics that represent state (like dimension tables or current configurations) rather than events. Without log compaction, a topic storing user profiles or job postings would grow indefinitely even if only a handful of records actually change.

**Tombstones** are special null-valued messages sent with a key to signal deletion. When a record should be removed from the compacted log entirely, you send a tombstone (a message with the key but null value). After log compaction runs, the tombstone itself is eventually removed, leaving no trace of that key. This matters because without tombstones, compaction would keep the last non-null value forever, making true deletes impossible.

Log compaction breaks applications that assume all historical events are preserved. If you're building an audit trail or calculating cumulative metrics (like total jobs posted ever), compaction will silently erase history. Conversely, if you're using Kafka as a changelog stream for materialized views or cache invalidation, log compaction is non-negotiable—it keeps state topics lean and queryable.

## Practice

**Problem:** Your `job_postings_fact` topic represents the current state of all job postings. When a job is filled and removed from the system, the record should be deleted. Without tombstones, old job IDs would still appear in the topic; without compaction, the topic size explodes as jobs are posted and removed repeatedly.

```sql
-- Producer logic: emit a tombstone to mark job deletion
-- When job_id = 456 is filled and removed:
INSERT INTO job_postings_fact 
  (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
VALUES 
  (456, NULL, NULL, NULL, NULL, NULL);

-- Consumer-side: after log compaction, only the latest state per job_id remains
-- Query compacted topic as changelog
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_fact
WHERE job_title_short IS NOT NULL;  -- filters out tombstones
```

## Notes

- **Compaction delay matters:** log compaction is not instant. Brokers compact segments asynchronously, so expect stale data briefly. Set `min.cleanable.dirty.ratio` and `min.compaction.lag.ms` based on your consistency requirements.
- **Tombstones have a lifetime:** set `delete.retention.ms` to control how long tombstones linger before permanent removal; too short and consumers miss deletes, too long and storage bloats.
- **Not a substitute for time-series events:** use compacted topics for state (current job posting details), but keep a separate topic for events (job posted, job filled, job expired). Never mix patterns.
- **Offset resets trip this up:** if a consumer resets to earliest, it will replay tombstones as nulls. Design your consumer to handle null values or skip them explicitly.
- **Adjacent topics:** changelog streams (Kstream changelog topics), exactly-once semantics (compaction interacts with transactional guarantees), and the difference between event streams vs. state streams.
