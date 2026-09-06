---
date: 2026-09-06
phase: streaming
topic: Apache Pulsar vs Kafka: when to consider switching
---

# Apache Pulsar vs Kafka: when to consider switching

*Streaming and distributed processing*

## Concept

Apache Pulsar and Apache Kafka both handle unbounded, unordered streams, but solve different operational pain points. Kafka excels at high-throughput, multi-subscriber architectures with simple partition-based ordering guarantees. Pulsar adds multi-tenancy, geo-replication, and tiered storage natively, making it attractive when you need to isolate workloads or manage data across regions without operational overhead. The switch matters when Kafka's consumer group model becomes a bottleneck—for instance, if you have dozens of independent teams consuming the same stream with conflicting retention policies, or if reprocessing historical data across a cluster becomes operationally expensive because it must live in hot storage.

The friction point is architectural: Kafka couples storage to brokers (scaling requires managing broker rebalancing), while Pulsar decouples storage from serving (you can scale readers independently and archive to cheaper tiered storage). Without this separation, replaying a week of historical events across 50 consumers wastes cluster resources. Similarly, Kafka's offset management per consumer group forces you to choose: either keep all retention for the slowest subscriber, or risk data loss. Pulsar's cursor management per subscription loosens this constraint, making it practical to support both fast and slow consumers on the same topic without coordination.

Choose Pulsar when you operate multiple data platforms with strict isolation requirements, need cost-effective long-term retention without provisioning hot storage, or serve internal and external consumers simultaneously with different SLAs. Stick with Kafka if you have deep operational expertise in Kafka, your workloads fit a single-region model, and throughput dominates your requirements.

## Practice

**Problem:** Job posting events arrive continuously and out of order by region. You need to calculate a rolling 24-hour window of average salary by job location, handling late arrivals (postings that arrive 6+ hours after the original event time). Kafka's default tumbling window approach would lose these late records; Pulsar's stateful function model handles them naturally, but you need to decide: is the operational complexity worth it?

```sql
-- Assuming event-time processing with allowed lateness
SELECT 
  window_time,
  job_location,
  ROUND(AVG(salary_year_avg), 2) AS avg_salary_24h,
  COUNT(*) AS posting_count,
  MAX(job_posted_date) AS latest_posting
FROM job_postings_fact
WINDOW TUMBLE (INTERVAL 24 HOUR, INTERVAL 6 HOUR ALLOWED LATENESS)
GROUP BY window_time, job_location
HAVING COUNT(*) >= 5
ORDER BY window_time DESC, avg_salary_24h DESC;
```

The SQL assumes your streaming engine (Flink, Spark Structured Streaming) respects event-time and late-arrival windows. On Kafka, you'd implement this with a stateful operator that buffers 6 hours of late data per location; on Pulsar, the same logic works identically, but backfill from tiered storage is cheaper if you need to replay.

## Notes

- **Offset vs. cursor confusion:** Kafka's consumer offset is committed per group and lost if the group is deleted; Pulsar's cursor is per subscription and persisted independently. This matters when you test a new consumer without blocking production—Pulsar doesn't force you to drain the topic first.

- **Geo-replication cost:** Kafka's cross-cluster replication is async and manual; Pulsar geo-replication is built-in but adds latency. For multi-region job posting ingestion, measure if the operational simplicity beats the extra round-trip latency.

- **Tiered storage tipping point:** Pulsar's tiered storage (S3, GCS) amortizes retention costs; Kafka requires you to either shrink retention or scale brokers. Re-examine this decision annually as your data volume grows.

- **Consumer lag monitoring:** Both systems expose lag, but Pulsar's decoupled storage makes lag less of a scaling emergency. Don't over-optimize for lag in Pulsar the way you would in Kafka.

- **Schema evolution and Avro/Protobuf:** Pulsar has built-in schema registry; Kafka usually pairs with Confluent Schema Registry. This is orthogonal to the sync/async debate but affects your data contract strategy across either platform.
