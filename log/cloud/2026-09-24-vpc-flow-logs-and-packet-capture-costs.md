---
date: 2026-09-24
phase: cloud
topic: VPC Flow Logs and packet capture costs
---

# VPC Flow Logs and packet capture costs

*Cloud platforms and storage*

## Concept

VPC Flow Logs capture network traffic metadata (source/destination IP, port, protocol, bytes, packets) flowing through your cloud infrastructure. Unlike full packet capture (PCAP), Flow Logs are metadata-only and far cheaper, but this tradeoff means you lose packet payload inspection. In data engineering, Flow Logs matter when diagnosing slow queries: they reveal whether latency stems from network saturation, dropped packets, rejected connections, or simply long transit times between your compute layer and data warehouse. Without them, you're blind to whether your 30-second query is slow because of bad SQL or because 15 GB crossed three subnets over a congested route.

The cost structure is critical: AWS charges ~$0.50 per million Flow Log records ingested, plus storage and query costs. A single m5.large EC2 instance can generate 50k–200k Flow Log records daily depending on traffic. For a 100-node Spark cluster querying S3 all day, you're easily looking at 10–50M records/day. Packet capture is 10–100× more expensive and rarely justified unless you're debugging corrupted frames or TCP resets at the byte level. Most performance issues resolve with Flow Logs alone.

## Practice

**Problem:** Your `job_postings_fact` table is replicated across a primary data warehouse in us-east-1 and a read replica in eu-west-1. A daily job in eu-west-1 that joins `job_postings_fact` with `applications_fact` (in the same region) suddenly takes 45 seconds instead of 3 seconds. You suspect cross-region traffic but have no evidence.

```sql
-- Query VPC Flow Logs to detect cross-region egress
SELECT 
  srcaddr,
  dstaddr,
  dstport,
  protocol,
  SUM(bytes) as total_bytes,
  SUM(packets) as total_packets,
  SUM(CASE WHEN action = 'REJECT' THEN packets ELSE 0 END) as rejected_packets,
  COUNT(*) as flow_records
FROM vpc_flow_logs
WHERE 
  srcaddr IN (SELECT private_ip FROM eu_west_1_instances WHERE cluster = 'analytics')
  AND dstaddr NOT IN (SELECT private_ip FROM eu_west_1_subnets)  -- non-local traffic
  AND start BETWEEN current_timestamp - interval 1 hour AND current_timestamp
GROUP BY srcaddr, dstaddr, dstport, protocol
ORDER BY total_bytes DESC
LIMIT 20;
```

This reveals whether the replica query is unexpectedly routing through NAT gateways or internet gateways (cross-region charge ≈$0.02/GB) instead of VPC peering. Rejected packets also hint at misconfigured security groups.

## Notes

- **VPC Flow Log ingestion lag:** Logs arrive 1–3 minutes delayed in CloudWatch or S3. Don't use them for real-time alerting; use them post-facto for root-cause analysis of incidents already reported by monitoring tools.
- **Sampling trap:** VPC Flow Logs have an optional sampling rate (1-in-N). Setting it to 10 or 100 cuts costs but can hide intermittent packet loss; disable sampling for 24–48 hours when troubleshooting, then re-enable.
- **Connects to:** Network ACLs, security groups, NAT gateway costs, and egress charges. A single misconfigured NACL or overly permissive security group can balloon both latency *and* costs; Flow Logs expose it.
- **Adjacent topic:** Enhanced monitoring on RDS and ECS also logs network stats, but at higher fidelity (per-query for RDS Insights). For application-to-database latency, combine Flow Logs with database query logs to isolate whether slowness is network or CPU.
- **Common mistake:** Parsing Flow Logs with string operations (`SUBSTRING`, `SPLIT`) in every query. Use a scheduled ETL to normalize them into a columnar format (Parquet) partitioned by date + hour, then query that; 10× faster and cheaper.
