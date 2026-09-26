---
date: 2026-09-26
phase: streaming
topic: Exactly-once semantics in Kafka producers
---

# Exactly-once semantics in Kafka producers

*Streaming and distributed processing*

## Concept

Exactly-once semantics (EOS) in Kafka producers means each message is written to the broker and persisted durably *exactly one time*—not zero times (lost) and not multiple times (duplicated). Without EOS, network failures or producer crashes between sending and receiving a broker acknowledgment can cause the same record to be written twice, silently corrupting fact tables and metrics.

Kafka achieves EOS for producers through **idempotence** and **transactional writes**. Idempotence (enabled via `enable.idempotence=true`) assigns each producer instance a unique ID and sequence number to each message; the broker deduplicates retries automatically. Transactional writes (via `transactional.id` and `begin_transaction()` / `commit_transaction()`) bundle multiple messages into an atomic unit, so either all succeed or all fail—critical when you're writing both a fact record and a dimension update in one logical operation.

The cost is latency and throughput: idempotent producers maintain in-flight request buffers, and transactions require broker-side state. In real-time data pipelines feeding analytics, the risk of duplicate job postings or salary records outweighs the performance cost.

## Practice

**Problem:** Your streaming job reads job postings from a Kafka topic and writes them to both a `job_postings_fact` table and a denormalized cache. A mid-pipeline failure (e.g., network partition after writing to the fact table but before updating the cache) causes the next retry to re-insert the same job posting, inflating row counts and breaking aggregates.

```sql
-- Without EOS: duplicate row appears
INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
VALUES (4521, 'Data Engineer', 125000, TRUE, '2024-01-15', 'Remote');

-- With EOS (pseudo-code logic): producer transaction wraps both writes atomically
BEGIN TRANSACTION (transactional_id='job_producer_001', producer_id='producer_1')
  INSERT INTO job_postings_fact (...) VALUES (...);
  UPDATE job_posting_cache SET last_updated = NOW() WHERE job_id = 4521;
COMMIT TRANSACTION;
-- Broker ensures both succeed or both roll back; retries are idempotent-deduplicated
```

## Notes

- **Idempotence + transactions are orthogonal:** idempotence handles single-message retries; transactions handle multi-message atomic writes. Use both for full EOS in Kafka.
- **Exactly-once is end-to-end myth:** Kafka EOS only covers producer→broker. Consumer side requires careful offset management and deduplication logic downstream (or consumer group isolation level tuning).
- **Adjacent: Kafka Consumer Isolation Levels** — `read_committed` vs. `read_uncommitted` determines whether consumers see transactional messages before commit; critical for multi-stage pipelines.
- **Common mistake:** enabling `enable.idempotence=true` without setting `acks=all`; idempotence requires durability, and `acks=all` (replica acknowledgment) is the only guarantee.
- **Revisit: delivery semantics ladder** — at-most-once (fast, lossy), at-least-once (duplicates possible), exactly-once (safe, slower). Know when each trade-off is acceptable for your domain.
