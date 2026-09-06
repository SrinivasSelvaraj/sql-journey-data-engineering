---
date: 2026-09-06
phase: streaming
topic: Scaling consumer groups without reprocessing
---

# Scaling consumer groups without reprocessing

*Streaming and distributed processing*

## Concept

When a Kafka consumer group processes a stream faster than expected, you scale by adding new consumers to partition the work. Without tracking offsets correctly, new consumers either reprocess all historical messages or skip data entirely—both unacceptable at scale. The key is that offset commits must survive consumer restarts and rebalances; they anchor each consumer to exactly where it left off, not where the stream started.

Scaling happens at the partition level: Kafka assigns partitions to consumers in a group, and new consumers claim idle partitions during a rebalance. If offsets aren't committed reliably before shutdown (or if they're committed to the wrong storage), the new consumer has no anchor and defaults to `auto.offset.reset` behavior, triggering either full replay or data loss. This matters most in production when you need to scale up at 3 AM without losing a single job posting or duplicating alerts.

The mechanics: set `enable.auto.commit=false`, manually commit offsets only after you've safely written results downstream (idempotent writes help here), and monitor consumer lag to detect if a consumer is stuck or falling behind.

## Practice

**Problem:** Your job postings stream is backed up; you have 50M unprocessed messages. You spin up a second consumer in the group to catch up. How do you ensure the new consumer starts exactly where the first one left off, without reprocessing or skipping?

```sql
-- Simulate offset tracking in a state table
CREATE TABLE job_postings_consumer_state (
  consumer_group STRING,
  partition INT,
  last_offset_committed BIGINT,
  last_processed_job_id BIGINT,
  commit_timestamp TIMESTAMP,
  PRIMARY KEY (consumer_group, partition)
);

-- On application startup, query the committed offset for each partition
SELECT partition, last_offset_committed
FROM job_postings_consumer_state
WHERE consumer_group = 'job_analytics_group'
ORDER BY partition;

-- After processing a batch of job postings, commit offset atomically with result
BEGIN;
  INSERT INTO job_postings_analytics (job_id, salary_bucket, work_from_home_count)
  SELECT job_id, 
         CASE WHEN salary_year_avg >= 100000 THEN 'high' ELSE 'low' END,
         CAST(job_work_from_home AS INT)
  FROM job_postings_fact
  WHERE job_id > (SELECT COALESCE(MAX(last_processed_job_id), 0) 
                  FROM job_postings_consumer_state
                  WHERE consumer_group = 'job_analytics_group');
  
  UPDATE job_postings_consumer_state
  SET last_offset_committed = 49999,
      last_processed_job_id = (SELECT MAX(job_id) FROM job_postings_fact),
      commit_timestamp = CURRENT_TIMESTAMP
  WHERE consumer_group = 'job_analytics_group' AND partition = 0;
COMMIT;
```

## Notes

- **Offset storage matters:** Kafka brokers store offsets in an internal topic by default, but you can also commit to external storage (database, Redis) for finer control and cross-system visibility.
- **Exactly-once semantics:** Manual offset commits work best when combined with idempotent writes downstream; if your analytics table uses `UPSERT ON job_id`, duplicate messages won't corrupt results.
- **Rebalance listeners:** Modern frameworks (Spark Structured Streaming, Flink) abstract away manual offset management, but understanding the underlying rebalance protocol is essential for debugging lag and consumer crashes.
- **Consumer lag monitoring:** Track `current_offset - log_end_offset` per partition; a growing lag means your new consumers still aren't fast enough—consider increasing parallelism further or optimizing the downstream write.
- **Adjacent topic:** Exactly-once delivery and idempotence are siblings; revisit them together when scaling stateful operations like windowed aggregations on job posting timestamps.
