---
date: 2026-10-18
phase: streaming
topic: Pulsar: geo-replication and multi-tenancy
---

# Pulsar: geo-replication and multi-tenancy

*Streaming and distributed processing*

## Concept

Pulsar's geo-replication enables clusters in different geographic regions to replicate messages asynchronously, ensuring data availability and reducing latency for distributed applications. Multi-tenancy allows a single Pulsar cluster to isolate workloads, data, and authentication across independent organizations or departments—critical when one customer's traffic spike or failure must not affect others. Together, they solve the problem of building resilient, globally-distributed systems where data consistency and isolation matter equally.

Geo-replication matters when your application serves users across continents and losing regional data is unacceptable, or when compliance requires data to stay within certain jurisdictions. Multi-tenancy becomes essential once you move from single-application deployments to platform-as-a-service models. Without proper replication, a regional outage loses data; without isolation, one tenant's consumer lag or burst traffic can starve another tenant's throughput.

The architecture relies on Pulsar's tiered storage and namespace-level isolation. Geo-replication uses a replicator process to forward entries between clusters; multi-tenancy uses namespaces (e.g., `tenant-a/namespace-1/topic`) and policies (quotas, authentication, backlog expiration) to enforce boundaries. When misconfigured, you'll see data loss during failover, cross-tenant message leakage, or one tenant monopolizing broker resources.

## Practice

**Problem:** A job board platform ingests job postings across North America and Europe. Postings must replicate across both regions within 5 seconds for local search APIs, and each customer (HR company) must see only their own postings in their namespace, with strict quotas to prevent one customer's bulk uploads from degrading others' read latency.

```sql
-- Set up multi-tenant topics with geo-replication
-- (Pulsar admin commands, not SQL, but shown in query-like format for clarity)

-- Create namespaces per tenant with replication across 'us-east' and 'eu-west' clusters
CREATE NAMESPACE hr_customer_a/jobs WITH 
  REPLICATION_CLUSTERS = ['us-east', 'eu-west']
  MESSAGE_RETENTION = 7 DAYS
  BACKLOG_QUOTA_LIMIT_BYTES = 10GB
  BACKLOG_QUOTA_POLICY = producer_exception;

CREATE NAMESPACE hr_customer_b/jobs WITH
  REPLICATION_CLUSTERS = ['us-east', 'eu-west']
  MESSAGE_RETENTION = 7 DAYS
  BACKLOG_QUOTA_LIMIT_BYTES = 10GB
  BACKLOG_QUOTA_POLICY = producer_exception;

-- Create tenant-isolated topic for job postings
CREATE TOPIC persistent://hr_customer_a/jobs/job_postings_fact;
CREATE TOPIC persistent://hr_customer_b/jobs/job_postings_fact;

-- Set subscription dispatch rate to prevent one tenant's consumer from overwhelming brokers
SET SUBSCRIPTION_DISPATCH_RATE = 10000 messages/second per namespace;

-- Set producer rate limit per tenant namespace
SET TOPIC_PUBLISH_RATE = 50000 messages/second per namespace;

-- Example: Insert job posting (producer sends to closest region, replicates to other)
INSERT INTO job_postings_fact (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
VALUES (1001, 'Senior Data Engineer', 145000, true, '2024-01-15', 'Toronto');
-- Message published to persistent://hr_customer_a/jobs/job_postings_fact
-- Replicated to eu-west cluster within ~2-5 seconds
```

## Notes

- **Replication lag is not zero:** Geo-replication is asynchronous; during network partitions, one region may temporarily diverge. Use application-level timestamps and idempotent consumption to handle re-delivery.
- **Namespace ≠ isolation guarantee:** A namespace isolates topics and quotas, but shares broker CPU and memory. Quota misconfiguration or a runaway consumer in one namespace can still affect others; monitor broker metrics per namespace.
- **Backlog quota policy matters:** `producer_exception` rejects writes when a tenant's unacknowledged messages exceed quota (fast-fail); `consumer_backlog_eviction` silently drops old messages (data loss). Choose based on whether you prefer rejection or silent degradation.
- **Cross-cluster consumer offsets:** Consumers in different regions track offsets separately per cluster. If a consumer fails over between regions, it may re-read messages; implement deduplication in your consumer logic.
- **Related:** Pulsar's authentication/authorization (tenant identity), tiered storage (cost optimization for geo-replicated backlog), and schema registry (multi-tenant schema governance) all compound the complexity—test them together.
