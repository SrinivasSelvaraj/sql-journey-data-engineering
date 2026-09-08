---
date: 2026-09-08
phase: streaming
topic: Tuning throughput: batch size, compression and parallelism
---

# Tuning throughput: batch size, compression and parallelism

*Streaming and distributed processing*

## Concept

Throughput tuning in streaming systems requires balancing three interdependent levers: **batch size** (how many records per micro-batch), **compression** (reducing network and storage I/O), and **parallelism** (number of concurrent tasks). When records arrive continuously and out of order, larger batches reduce per-record overhead and improve network efficiency, but increase latency and memory pressure. Compression shrinks payload size—critical when ingesting high-volume job postings across unstable networks—but adds CPU cost that can bottleneck if parallelism is too low. Without tuning, you either starve resources (batches too small, no compression, single-threaded) or overflow them (batches too large, over-compression overhead, contention from excessive parallelism).

The sweet spot depends on your stream rate, cluster resources, and SLA. A job posting pipeline ingesting 10k events/sec needs different tuning than one at 100 events/sec. Compression pays off above ~1 MB/sec throughput; below that, CPU overhead wastes cycles. Parallelism should match available cores and partition count—parallelizing beyond partitions causes shuffling overhead that negates gains.

## Practice

**Problem:** You're streaming job postings into a data lake. The ingest is 50k events/sec, network bandwidth is limited to 100 Mbps, and you have a 16-core worker. Current config: batch size 1000 records (~2 MB uncompressed), no compression, 4 parallel tasks. Latency SLA is 5 seconds. Calculate if this will work and propose tuning.

```sql
-- Diagnostic query: estimate throughput without compression
-- Assume avg job posting ~2 KB uncompressed
WITH config AS (
  SELECT 
    50000 as events_per_sec,
    2000 as bytes_per_event_uncompressed,
    1000 as batch_size,
    1.0 as compression_ratio,  -- no compression
    4 as parallel_tasks,
    5 as latency_sla_sec
)
SELECT
  events_per_sec,
  events_per_sec * bytes_per_event_uncompressed / 1_000_000 as uncompressed_mbps,
  (events_per_sec * bytes_per_event_uncompressed / 1_000_000) * compression_ratio as compressed_mbps,
  100 as network_limit_mbps,
  CASE 
    WHEN (events_per_sec * bytes_per_event_uncompressed / 1_000_000) * compression_ratio > 100 
    THEN 'EXCEEDS BANDWIDTH'
    ELSE 'OK'
  END as network_status,
  batch_size / (events_per_sec / 1000.0) as batch_latency_ms,
  CASE
    WHEN (batch_size / (events_per_sec / 1000.0)) > latency_sla_sec * 1000
    THEN 'EXCEEDS SLA'
    ELSE 'OK'
  END as latency_status,
  parallel_tasks,
  CASE
    WHEN parallel_tasks > 16 THEN 'Over-parallelized (>16 cores)'
    WHEN parallel_tasks < 16 / 2 THEN 'Under-parallelized'
    ELSE 'OK'
  END as parallelism_status
FROM config;

-- Proposed tuning: increase compression + batch size + parallelism
-- Batch size 5000 (25ms @ 50k/sec), gzip compression (0.3x), 8 parallel tasks
WITH proposed_config AS (
  SELECT 
    50000 as events_per_sec,
    2000 as bytes_per_event_uncompressed,
    5000 as batch_size,
    0.3 as compression_ratio,  -- gzip ~70% reduction
    8 as parallel_tasks,
    5 as latency_sla_sec
)
SELECT
  'PROPOSED' as config,
  (events_per_sec * bytes_per_event_uncompressed / 1_000_000) * compression_ratio as compressed_mbps,
  100 as network_limit_mbps,
  batch_size / (events_per_sec / 1000.0) as batch_latency_ms,
  parallel_tasks
FROM proposed_config;
```

**Solution:** Uncompressed throughput is 100 Mbps—exactly at limit with no headroom. Add gzip (0.3x ratio) to drop to 30 Mbps, increase batch size to 5000 for 25 ms latency (well under 5 sec SLA), and scale parallelism to 8 tasks (8 cores × 2 for context switching headroom). This keeps CPU at ~50% and leaves network bandwidth for spikes.

## Notes

- **Common mistake:** Setting batch size too high to "maximize throughput" without checking latency SLA; 10k-record batches at 50
