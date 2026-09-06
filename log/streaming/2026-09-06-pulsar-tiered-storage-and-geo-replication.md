---
date: 2026-09-06
phase: streaming
topic: Pulsar: tiered storage and geo-replication
---

# Pulsar: tiered storage and geo-replication

*Streaming and distributed processing*

## Concept

Pulsar's tiered storage separates hot data (recent messages in broker memory/disk) from cold data (archived in cheaper object storage like S3). As streaming workloads grow, broker disk becomes a bottleneck; tiered storage lets you retain months of history without proportional infrastructure cost. Geo-replication synchronously or asynchronously mirrors topic data across datacenters, ensuring failover resilience and enabling local reads in multi-region deployments.

These features matter together because streaming data is *immutable and append-only*—you cannot delete old records cheaply, only archive them. Without tiered storage, retention policies force you to choose between short TTLs (losing historical context for late-arriving consumers) or massive disk provisioning. Without geo-replication, a regional outage silences the entire topic; with it, a replica region absorbs reads and writes transparently.

Without both, you either hemorrhage money on storage or lose data durability and multi-region availability—the exact guarantees streaming systems are built to provide.

## Practice

**Problem:** Job postings arrive in real-time to a Pulsar topic. You want to:
- Keep the last 30 days of postings hot for low-latency reprocessing by analytics.
- Archive older postings to S3 for compliance and ML training (cold read, high latency tolerated).
- Replicate the topic across US-East and EU-West datacenters so regional failures don't drop job updates.

Configure tiered storage threshold and geo-replication:

```sql
-- Pulsar Admin CLI equivalent (not SQL, but the operational definition)
-- Create topic with tiered storage and geo-replication

pulsar-admin topics create-partitioned-topic \
  persistent://public/default/job_postings \
  --partitions 10

pulsar-admin topics set-retention \
  persistent://public/default/job_postings \
  --size -1 \
  --time 30d

pulsar-admin topics set-offload-policies \
  persistent://public/default/job_postings \
  --driver s3 \
  --s3-bucket job-postings-archive \
  --offload-threshold-in-bytes 104857600 \
  --offload-threshold-in-seconds 86400

pulsar-admin topics set-replication \
  persistent://public/default/job_postings \
  --replication-clusters us-east-1,eu-west-1
```

For a consumer reading job_postings_fact:
- Messages from the last 30 days are served from broker cache (ms latency).
- Older messages trigger offload retrieval from S3 (~100ms–1s, acceptable for historical queries).
- If us-east-1 broker dies, the eu-west-1 replica handles all traffic with no topic unavailability.

## Notes

- **Tiered storage overhead:** Offload is automatic but not free—every message written incurs a serialization cost. Monitor offload lag; if brokers can't keep up, increase `managedLedgerOffloadMaxThreads`.
- **Geo-replication consistency:** Async replication introduces lag; if you read from multiple regions in the same transaction, you may see stale data. Use geo-location affinity or sync replication for strong consistency, accepting latency cost.
- **Cold storage queries are slow:** Offloaded data lives in S3, not indexed. Don't expect sub-second reads on 6-month-old postings; pair tiered storage with a data lake (e.g., Iceberg, Delta) for analytical queries.
- **Retention vs. offload:** Retention *keeps* data; offload *moves* it. Set retention longer than your hot window; offload kicks in after `offload-threshold-in-seconds`. Misconfig = accidental deletion.
- **Adjacent topics:** Message ordering (Pulsar keys enforce ordering per key); exactly-once semantics (replication can cause duplicates on failover); Pulsar Functions for stream processing (they read tiered data transparently).
