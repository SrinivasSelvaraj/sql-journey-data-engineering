---
date: 2026-10-17
phase: streaming
topic: Kafka transactions: isolation level and exactly-once semantics
---

# Kafka transactions: isolation level and exactly-once semantics

*Streaming and distributed processing*

## Concept

Kafka transactions ensure that a producer can write multiple messages atomically, and a consumer can read them atomically—either all succeed or none do. This is critical in streaming pipelines where a failure mid-batch can leave your system in an inconsistent state: you might write transformed data to a sink while losing the offset commit, causing reprocessing, or commit an offset before writing results, causing data loss.

Isolation levels control what a consumer sees during concurrent writes. With `read_uncommitted` (default), you see all messages immediately, including those from failed transactions. With `read_committed`, you only see messages from completed transactions, eliminating the "phantom read" problem where a consumer processes a message that later gets aborted. The trade-off is latency—`read_committed` must wait for the broker to confirm a transaction's outcome.

Exactly-once semantics (EOS) in Kafka combines producer idempotence (deduplication via sequence numbers), transactional writes, and `read_committed` consumers to guarantee no duplicates and no data loss, even across producer crashes or broker failures. Without it, at-least-once delivery is the norm—your pipeline reprocesses data on retry, which corrupts aggregations, double-counts revenue, or overwrites recent state with stale values.

## Practice

**Problem:** A real-time job posting pipeline reads from Kafka, joins job_postings with salary data, and writes enriched records to both a data warehouse table and a metrics topic. If the process crashes after writing to the warehouse but before publishing metrics, the next restart reprocesses the same batch, double-counting job postings in downstream dashboards.

```sql
-- Producer side: Enable transactions and idempotence
SET enable.idempotence = true;
SET transactional.id = "job-enrichment-pipeline-1";  -- Must be unique per producer instance

-- In application code (pseudocode):
producer.beginTransaction()
try {
  EnrichedRecord enriched = enrichJob(raw_job_posting);
  warehouse.write(enriched);      -- Write to DW
  metrics_topic.send(enriched);   -- Publish metrics
  producer.commitTransaction()    -- Both succeed atomically
} catch (Exception e) {
  producer.abortTransaction()     -- Rollback both
  throw e
}

-- Consumer side: Enable read_committed isolation
SET isolation.level = read_committed;

-- This ensures the consumer only sees committed job postings:
SELECT job_id, job_title_short, salary_year_avg 
FROM job_postings_fact 
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
-- Data arrived via a committed Kafka transaction
```

## Notes

- **Common mistake:** Setting `transactional.id` to a static string shared across producer instances causes conflicts; use instance-specific IDs (e.g., hostname + pid) or rely on consumer group assignment for EOS in Kafka Streams.
- **Overhead cost:** Transactions add latency (2–3x slower in some workloads) and require additional broker state. Profile your use case—if duplicates are acceptable or easily deduplicated downstream, at-least-once may be sufficient.
- **Consumer lag reality:** `read_committed` consumers lag behind the latest offset because they wait for transaction markers. Monitor LSO (Last Stable Offset) separately from LEO (Log End Offset).
- **Exactly-once scope:** Kafka EOS only guarantees exactly-once *within* Kafka. End-to-end exactly-once requires idempotent sinks (e.g., upserts with unique keys in the warehouse); a non-idempotent sink (insert-only) breaks the guarantee.
- **Adjacent topics:** Understand Kafka's `__transaction_state` topic, consumer group coordination, and how `max.in.flight.requests.per.connection` interacts with transactional ordering constraints.
