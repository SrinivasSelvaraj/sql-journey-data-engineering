---
date: 2026-09-26
phase: streaming
topic: Tombstones and deletion markers in log-compacted topics
---

# Tombstones and deletion markers in log-compacted topics

*Streaming and distributed processing*

## Concept

A tombstone is a special record—typically a message with a null or empty value—sent to a log-compacted topic to signal deletion of a key. In Kafka log-compacted topics, the broker retains only the latest value for each key, discarding older records. When you want to delete a fact, you cannot simply remove the record; instead, you emit a tombstone (key + null value) so that downstream consumers and state stores see the deletion, and the broker eventually purges the key entirely after the delete retention window.

Without tombstones, a downstream consumer replaying a log-compacted topic would resurrect deleted entities. For example, a job posting marked as closed would reappear as "open" when a new consumer reads the compacted log from the beginning. Tombstones ensure that deletions propagate correctly to stream processors, databases, and caches, preventing stale data from leaking into your pipeline.

The timing matters: a tombstone must be produced *before* the consumer lag catches up to it, or the consumer may miss the deletion signal. After the delete retention period (e.g., 24 hours), the broker removes the tombstone itself, keeping only the compacted log clean.

## Practice

**Problem:** Your analytics platform ingests job postings into a log-compacted topic. When a job posting is closed or retracted, the event system should delete it from all downstream views. You need to ensure that a retracted job posting does not appear in a "currently open jobs" report, even if a new consumer starts from the beginning of the topic.

```sql
-- Producer side (pseudo-code conceptual SQL):
-- When a job is closed, emit a tombstone to the compacted topic:
INSERT INTO job_postings_fact (job_id, ...) VALUES (42, NULL, NULL, NULL, NULL, NULL);
-- key=42, value=NULL signals deletion

-- Consumer side: stream processor filters out tombstones
SELECT job_id, job_title_short, salary_year_avg
FROM job_postings_fact
WHERE job_id IS NOT NULL  -- filter out tombstone records
  AND job_work_from_home IS NOT NULL
ORDER BY job_posted_date DESC;
```

## Notes

- **Common mistake:** Treating a log-compacted topic like a regular topic and expecting DELETE operations to work; you must explicitly produce tombstones or use a schema registry marker (e.g., `null` payload).
- **Delete retention window matters:** If a consumer lags longer than the delete retention period, it will never see the tombstone and may replay stale deleted records; monitor consumer lag closely.
- **Connects to:** Kstream state store cleanup, changelog topics in Kafka Streams, and event sourcing patterns where deletion is first-class.
- **Schema registry consideration:** Some frameworks (Avro, Protobuf) support special markers for deletion; document your convention to avoid ambiguity between "null value" and "deleted entity."
- **Revisit:** Log compaction policy tuning (min.cleanable.dirty.ratio, segment.ms) to ensure tombstones and deletions are handled predictably in production.
