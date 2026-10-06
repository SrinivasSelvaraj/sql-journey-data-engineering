---
date: 2026-10-06
phase: python
topic: Pickle security: deserialization attacks and alternatives
---

# Pickle security: deserialization attacks and alternatives

*Python for data engineering*

## Concept

Pickle is Python's native serialization format, but it executes arbitrary code during deserialization. If you unpickle untrusted data—from user uploads, message queues, cached files, or compromised sources—an attacker can inject malicious bytecode that runs on your system. This is not a parsing bug; it's by design. In data pipelines, this matters because you often deserialize intermediate results: cached feature sets, checkpoint files, or messages from external systems.

The risk materializes when your pipeline accepts pickled input without validation. For example, loading a `.pkl` file from a data lake without knowing its origin, or unpickling an object from a Kafka topic. A malicious actor can craft a pickle that deletes files, exfiltrates data, or compromises your infrastructure—all invisibly during the `pickle.load()` call.

**Alternatives exist and are safer**: JSON for structured data (no code execution), MessagePack or Protocol Buffers for binary formats with schema safety, and Parquet for tabular data. If you must use pickle, restrict it to trusted internal sources and sign serialized objects with HMAC.

## Practice

**Problem:** You're building a feature cache for a real-time job salary prediction model. Pipeline stages serialize intermediate job records to S3 for reuse across teams. A junior engineer suggests pickling the objects for speed. What's the risk, and how should you serialize instead?

```sql
-- Schema: job_postings_fact
-- Problem: pickle allows arbitrary code execution on deserialization
-- Solution: Use JSON or Parquet instead

-- Option 1: Export to JSON Lines (schema-safe, human-readable)
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CURRENT_TIMESTAMP AS cached_at
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
-- Output: Write to S3 as .jsonl with schema validation on read

-- Option 2: Export to Parquet (columnar, compressed, strongly typed)
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_fact
WHERE job_posted_date >= CURRENT_DATE - INTERVAL 7 DAY
-- Output: Write to S3 as .parquet with Arrow schema enforcement
```

In Python, read with `pandas.read_json(..., dtype={...})` or `pandas.read_parquet(...)` instead of `pickle.load()`. Both validate schema on read; neither executes code.

## Notes

- **Never unpickle untrusted data.** Even from "internal" sources if they can be modified (compromised S3 bucket, intercepted queue message). Treat pickle like `eval()`.
- **Pickle versioning is fragile.** If your class definition changes, old pickles silently fail or behave unexpectedly. JSON/Parquet decouple format from code.
- **Signing doesn't fully mitigate the issue.** HMAC proves origin but doesn't prevent the code execution itself. Use it only as a *second* layer after filtering by source.
- **Connect to schema evolution and data contracts.** Parquet and JSON schemas let you version and validate structure. Pickle offers no contractual guarantees; it's a black box until unpickling.
- **Checkpoint/cache serialization is a common blind spot.** Teams often pickle ML model checkpoints or feature caches without thinking about supply-chain risk. Audit all deserialization points in your DAG.
