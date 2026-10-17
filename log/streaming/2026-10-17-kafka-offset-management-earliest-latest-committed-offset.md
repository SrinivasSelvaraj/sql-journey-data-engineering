---
date: 2026-10-17
phase: streaming
topic: Kafka offset management: earliest, latest, committed offset
---

# Kafka offset management: earliest, latest, committed offset

*Streaming and distributed processing*

## Concept

Kafka offset management determines where a consumer resumes reading from a topic partition. The **committed offset** is the last message your consumer explicitly acknowledged as processed; **earliest** means starting from partition offset 0 (oldest available message); **latest** means starting from the next message not yet written (catch-up mode). Without explicit offset management, you either reprocess old data wastefully or skip messages entirely if your consumer restarts.

In practice, you choose a strategy: use `auto.offset.reset=earliest` during development and backfill scenarios to guarantee no data loss, and `auto.offset.reset=latest` for real-time dashboards where you only care about fresh events. The committed offset is persisted (typically in Kafka's `__consumer_offsets` topic) so that if your consumer crashes and restarts, it picks up exactly where it left. If your application writes offsets to Kafka *before* it finishes processing (not after), a failure mid-process means data loss or duplication.

## Practice

**Problem:** You're consuming job posting events from Kafka and upserting them into `job_postings_fact`. Your consumer crashes after reading 5,000 events but before writing all 5,000 to the data warehouse. On restart, you need to reprocess those 5,000 events without losing any, then continue from the last committed offset. Show how to handle offset commits safely.

```sql
-- Pseudo-code approach: consume, process, *then* commit
-- (Language: Python/Java Kafka consumer pattern)

consumer = KafkaConsumer(
    'job_postings_topic',
    group_id='job_postings_etl',
    auto_offset_reset='earliest',  -- Start from beginning if no offset stored
    enable_auto_commit=False         -- Manual offset commit control
)

for message in consumer:
    job_event = json.loads(message.value)
    
    -- UPSERT into data warehouse (idempotent by job_id)
    INSERT INTO job_postings_fact 
      (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
    VALUES (job_event['id'], job_event['title'], job_event['salary'], 
            job_event['remote'], job_event['posted'], job_event['location'])
    ON CONFLICT (job_id) DO UPDATE SET ...;
    
    -- Only commit *after* warehouse write succeeds
    consumer.commit()
```

## Notes

- **Offset commit timing is critical:** commit after your sink write succeeds, not before. If you commit early and crash, you skip unprocessed messages. If you commit late, you risk reprocessing duplicates—mitigate with idempotent upserts (keyed by `job_id`).
- **auto.offset.reset only applies when no committed offset exists:** once your consumer group has committed an offset, this setting is ignored on restart.
- **Consumer group coordination:** multiple consumers reading the same topic partition will conflict; Kafka assigns partitions to group members. Monitor lag with tools like Confluent Control Center or Burrow to catch slow consumers.
- **Exactly-once semantics requires transactions:** offset commits + data writes must be atomic. Use Kafka transactions or write offsets to your warehouse alongside data (idempotent write + offset together).
- **Adjacent topics:** consumer lag monitoring, rebalancing strategy (`RoundRobin` vs `Range`), and dead-letter queues for poison-pill messages that break parsing.
