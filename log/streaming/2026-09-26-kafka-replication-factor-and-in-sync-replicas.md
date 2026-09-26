---
date: 2026-09-26
phase: streaming
topic: Kafka replication factor and in-sync replicas
---

# Kafka replication factor and in-sync replicas

*Streaming and distributed processing*

## Concept

A **replication factor** is the number of broker copies Kafka maintains for each partition. A factor of 3 means three identical copies across three different brokers. When a leader broker fails, Kafka promotes an in-sync replica (ISR) to leader, ensuring the topic survives node loss.

**In-sync replicas (ISR)** are followers that have caught up with the leader's latest offset. Only ISRs are eligible for promotion; a replica lagging behind (due to network delays or slow disk I/O) is *out of sync* and cannot become leader. This prevents data loss: if the leader dies and only an out-of-sync replica exists, you lose committed messages.

Without proper replication and ISR management, a single broker failure means partition unavailability and potential message loss. High replication factors cost disk and network bandwidth but are non-negotiable for systems where lost events (financial transactions, user actions) cascade into analytics errors. The default min.insync.replicas (often 1) is dangerous—set it to 2 or more in production to guarantee a quorum survives broker loss.

## Practice

**Problem:** Your streaming pipeline ingests job postings into Kafka topic `job_postings_raw`. Each posting must be reliably stored and later loaded into the warehouse. You've configured replication factor 3 but set min.insync.replicas to 1. A broker crashes mid-stream. A message was written to the leader but not yet replicated to followers. What went wrong, and how do you query the warehouse to detect missing records?

```sql
-- Detect gaps in job posting ingestion by checking for missing job_ids
-- Assuming job_postings_fact is loaded from Kafka after replication

-- Compare expected sequence to actual:
WITH expected AS (
  SELECT 
    ROW_NUMBER() OVER (ORDER BY job_posted_date, job_id) AS expected_seq,
    job_id
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE
),
actual AS (
  SELECT 
    ROW_NUMBER() OVER (ORDER BY job_posted_date, job_id) AS actual_seq,
    job_id
  FROM job_postings_fact
  WHERE job_posted_date = CURRENT_DATE
)
SELECT 
  COUNT(*) AS missing_postings
FROM expected e
LEFT JOIN actual a ON e.expected_seq = a.actual_seq
WHERE a.job_id IS NULL;

-- Fix: Set min.insync.replicas=2 in topic config so broker must confirm to ≥2 replicas before acking.
-- This guarantees at least 2 copies exist; losing 1 broker leaves 1 ISR to promote.
```

## Notes

- **min.insync.replicas=1 is a trap:** Default configs allow acks=all to complete with only the leader, defeating replication's purpose. Always pair acks=all with min.insync.replicas ≥ 2.
- **ISR shrinkage signals trouble:** Monitor replica.lag.max.bytes and broker logs. If ISRs drop, followers are falling behind—check disk I/O, network, or GC pauses; data loss looms if the leader dies before ISR recovers.
- **Trade-off: durability vs. latency:** Higher min.insync.replicas and replication factor increase latency (more acks to wait for) but lower loss risk. For job postings, durability usually wins; for metrics, you might accept replication factor 2 / min.insync.replicas 1.
- **Connects to:** acks configuration (all/1/0), consumer group offset commits (also need replication), and broker-side __consumer_offsets topic (must itself be replicated to prevent offset loss).
- **Revisit:** Unclean leader election (unclean.leader.election.enable) and how it can promote out-of-sync replicas as a last resort, trading correctness for availability.
