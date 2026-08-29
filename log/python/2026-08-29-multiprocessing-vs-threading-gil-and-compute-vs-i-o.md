---
date: 2026-08-29
phase: python
topic: Multiprocessing vs threading: GIL and compute vs I/O
---

# Multiprocessing vs threading: GIL and compute vs I/O

*Python for data engineering*

## Concept

The Global Interpreter Lock (GIL) in CPython allows only one thread to execute Python bytecode at a time, making threading ineffective for CPU-bound workloads but suitable for I/O-bound tasks. In data pipelines, this distinction is critical: if your code waits on network requests, database queries, or file I/O, threading lets other threads run during those waits. If your code does heavy computation—parsing JSON, transforming rows, aggregating numbers—the GIL means threads will serialize anyway, wasting context-switch overhead. Multiprocessing spawns separate Python processes with independent GILs, enabling true parallelism for compute but at the cost of higher memory and serialization overhead (pickling objects across process boundaries).

For data engineering pipelines, the choice determines whether you're solving a real bottleneck or creating false parallelism. A pipeline that fetches 10,000 job postings from an API benefits from threading—spawn 10 threads, each fetching batches while others wait. The same pipeline running a complex regex or statistical transformation on those rows should use multiprocessing. Mixed workloads (fetch data *then* transform) often require process-level parallelism for the compute phase and connection pooling within each process for I/O.

Without this awareness, you'll write thread-based pipelines that feel fast locally but saturate CPU without improving throughput, or use multiprocessing everywhere and exhaust memory or serialize so much data that network and disk I/O become the new bottleneck.

## Practice

**Problem:** You are ingesting job postings into a fact table. The pipeline must fetch postings from an external API (I/O-bound), clean and deduplicate them by job_id (compute-bound), then insert into the database (I/O-bound). Your current single-threaded script processes 100 postings/second but needs to handle 5,000/second.

```python
from concurrent.futures import ThreadPoolExecutor, ProcessPoolExecutor
import requests
import json
from typing import List, Dict
from datetime import datetime

def fetch_job_batch(offset: int, limit: int = 100) -> List[Dict]:
    """I/O-bound: fetch from API with retries."""
    response = requests.get(
        "https://api.example.com/jobs",
        params={"offset": offset, "limit": limit},
        timeout=10
    )
    response.raise_for_status()
    return response.json().get("data", [])

def clean_and_dedupe(batch: List[Dict]) -> List[Dict]:
    """Compute-bound: parse, validate, deduplicate."""
    seen = set()
    cleaned = []
    for job in batch:
        job_id = job.get("job_id")
        if job_id not in seen and job_id:
            seen.add(job_id)
            cleaned.append({
                "job_id": job_id,
                "job_title_short": job.get("title", "")[:50],
                "salary_year_avg": int(job.get("salary", 0)),
                "job_work_from_home": job.get("remote", False),
                "job_posted_date": datetime.fromisoformat(job.get("posted_at")).date(),
                "job_location": job.get("location", "")[:100]
            })
    return cleaned

def insert_jobs(batch: List[Dict], db_connection) -> int:
    """I/O-bound: batch insert."""
    cursor = db_connection.cursor()
    cursor.executemany(
        """INSERT INTO job_postings_fact 
           (job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, job_location)
           VALUES (%(job_id)s, %(job_title_short)s, %(salary_year_avg)s, %(job_work_from_home)s, %(job_posted_date)s, %(job_location)s)
           ON CONFLICT (job_id) DO NOTHING""",
        batch
    )
    db_connection.commit()
    return len(batch)

def ingest_pipeline(total_jobs: int, db_connection):
    """Hybrid threading + multiprocessing pipeline."""
    # Phase 1: Fetch in parallel (I/O-bound, use threads)
    fetched_batches = []
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = [
            executor.submit(fetch_job_batch, offset)
            for offset in range(0, total_jobs, 100)
        ]
        for future in futures:
            fetched_batches.append(future.result())
    
    # Phase 2: Clean and dedupe in parallel (compute-bound, use processes)
    flattened = [job for batch in fetched_batches for job in batch]
    with ProcessPoolExecutor(max_workers=4) as executor:
        cleaned_batches = list(executor.map(
            clean_and_dedupe,
            [flatt
