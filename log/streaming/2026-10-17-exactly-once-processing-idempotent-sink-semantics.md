---
date: 2026-10-17
phase: streaming
topic: Exactly-once processing: idempotent sink semantics
---

# Exactly-once processing: idempotent sink semantics

*Streaming and distributed processing*

## Concept

An idempotent sink is one where writing the same record multiple times produces the same result as writing it once. In streaming systems, failures (network timeouts, process crashes, broker acknowledgment delays) force frameworks to retry operations. Without idempotent semantics, a retry can create duplicates, causing aggregate counts to inflate, balance sheets to misstate, and metrics to diverge from reality. Exactly-once *processing* guarantees are often impossible in distributed systems (the two-phase commit is expensive and fragile), but exactly-once *output* becomes achievable through idempotency: if you can detect and skip duplicate writes, retries become safe.

The key is making writes replayable. Idempotent sinks typically rely on one of two patterns: *deduplication by natural key* (detecting that this record was already written and skipping it) or *upsert semantics* (using a unique constraint or merge operation so a second write overwrites the first without duplication). Without this, a single logical message delivered twice produces two physical rows. In high-throughput systems with frequent failures, this silent data corruption spreads quickly and becomes expensive to detect and repair.

## Practice

**Problem:** A streaming job reads job postings from Kafka and writes to `job_postings_fact`. A network hiccup causes a batch to be written, the write appears to fail on the client side, and the framework retries. The same 50 job postings are now duplicated in the table. You need to ensure that regardless of retries, each unique job posting appears exactly once.

```sql
-- Idempotent sink using MERGE (upsert)
MERGE INTO job_postings_fact AS target
USING staging_job_postings AS source
  ON target.job_id = source.job_id
    AND target.job_posted_date = source.job_posted_date
WHEN MATCHED THEN
  UPDATE SET
    job_title_short = source.job_title_short,
    salary_year_avg = source.salary_year_avg,
    job_work_from_home = source.job_work_from_home,
    job_location = source.job_location
WHEN NOT MATCHED THEN
  INSERT (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
  VALUES (source.job_id, source.job_title_short, source.salary_year_avg, source.job_work_from_home, source.job_posted_date, source.job_location);
```

The composite key `(job_id, job_posted_date)` ensures idempotency: a second write of the same posting simply updates the row in place rather than inserting a duplicate.

## Notes

- **Deduplication is not free:** Checking for duplicates requires a lookup (hash join, index scan, or bloom filter). In high-throughput sinks, this can become a bottleneck; choose a natural key that is both selective and readily indexed.

- **Confusing with at-least-once delivery:** Exactly-once *output* is achievable without exactly-once *delivery*. Your Kafka consumer may receive a message twice; idempotent sinks tolerate that. This is pragmatic; true exactly-once delivery across a cluster requires consensus and is much costlier.

- **State snapshots matter:** Idempotent sinks alone do not guarantee consistency of derived state. A stream processor writing to multiple sinks (fact table + dimension table) can still violate referential integrity if one sink fails and retries while the other succeeds. Combine idempotency with transactional writes and/or watermarks.

- **Related: deduplication windows and bloom filters.** For append-only logs where the natural key is not immediately available, you may maintain a sliding window of recently seen IDs in memory or a distributed bloom filter to reject late duplicates without a full database join.

- **Revisit checkpoint and savepoint semantics:** A streaming framework's ability to replay from a checkpoint is only safe if your sink is idempotent. Design this assumption into your architecture early.
