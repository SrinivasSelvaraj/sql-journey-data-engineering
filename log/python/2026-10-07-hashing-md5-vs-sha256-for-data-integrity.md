---
date: 2026-10-07
phase: python
topic: Hashing: MD5 vs SHA256 for data integrity
---

# Hashing: MD5 vs SHA256 for data integrity

*Python for data engineering*

## Concept

Hash functions create fixed-length fingerprints of data; MD5 (128-bit) and SHA256 (256-bit) differ in collision resistance and performance. MD5 is cryptographically broken—two different inputs can produce the same hash—making it unsuitable for integrity verification in production pipelines. SHA256 is collision-resistant and the standard for detecting accidental corruption or tampering during ETL. Use SHA256 when you need to verify that a record hasn't changed between source and destination, or to detect duplicate rows in a stream without storing the full record.

In data pipelines, hashing solves the "did this row get corrupted in transit?" problem. When copying sensitive data or relying on checksums for reconciliation, a single-byte corruption should produce a completely different hash. MD5's vulnerabilities mean a malicious actor can craft collisions deliberately; SHA256 makes that computationally infeasible. Without hashing, you only know a record arrived; you don't know it arrived *correctly*.

## Practice

**Problem:** Load job postings into a warehouse. You must detect if any row was corrupted or duplicated during the extract phase, and log a warning if the same posting appears twice with identical attributes.

```sql
-- Add hash column to detect duplicates and corruption
ALTER TABLE job_postings_fact
ADD COLUMN row_hash VARCHAR(64);

-- Compute SHA256 of all non-surrogate columns
UPDATE job_postings_fact
SET row_hash = SHA2(
    CONCAT(
        job_title_short, '|',
        salary_year_avg, '|',
        job_work_from_home, '|',
        job_posted_date, '|',
        job_location
    ),
    256
);

-- Detect duplicates: same hash, same job_id (should not happen)
SELECT 
    job_id,
    COUNT(*) as occurrence_count,
    row_hash
FROM job_postings_fact
GROUP BY job_id, row_hash
HAVING COUNT(*) > 1;

-- Detect rows with identical content but different job_ids (true duplicates)
SELECT 
    row_hash,
    COUNT(DISTINCT job_id) as distinct_job_ids,
    COUNT(*) as total_rows
FROM job_postings_fact
GROUP BY row_hash
HAVING COUNT(DISTINCT job_id) > 1
ORDER BY total_rows DESC;
```

## Notes

- **MD5 is legacy only**: never use it for data integrity validation. It's acceptable only for non-security contexts (e.g., legacy system compatibility) where collisions don't matter.
- **SHA256 is the pipeline standard**: computationally fast enough for row-level hashing in Python and SQL, collision-resistant, and widely supported. SHA512 is overkill for integrity checks.
- **Hash nulls carefully**: `CONCAT()` in SQL treats NULL as empty string; decide whether nulls should hash identically or be excluded from the hash computation to avoid silent bugs.
- **Connects to**: checksums in file transfer (sftp, s3), deduplication in data lakes, incremental load detection (hash as a change indicator), and data lineage tracking.
- **Revisit in typed Python**: use `hashlib.sha256()`, encode strings to bytes, store hashes as hex strings; type hints clarify intent (e.g., `def compute_row_hash(record: dict) -> str`).
