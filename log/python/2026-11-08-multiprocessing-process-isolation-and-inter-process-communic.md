---
date: 2026-11-08
phase: python
topic: Multiprocessing: process isolation and inter-process communication
---

# Multiprocessing: process isolation and inter-process communication

*Python for data engineering*

## Concept

Multiprocessing spawns separate Python processes, each with its own memory space and interpreter. Unlike threading (which shares memory within a single process), each process is completely isolated—no shared state, no global variables, no race conditions on data structures. This isolation is crucial for CPU-bound data engineering tasks: parsing gigabytes of CSV files, transforming records in parallel, or running independent pipeline stages without one failure corrupting another's state.

Inter-process communication (IPC) must be explicit: queues, pipes, or shared memory objects passed through function signatures. This explicitness is the price of safety. When you pass data between processes, Python serializes it (pickle by default), which forces you to think about what's actually moving through your pipeline. Bad input in one process cannot silently corrupt another's memory.

Without process isolation, a segfault in a NumPy operation, an out-of-memory error, or a hung thread can take down your entire pipeline. With it, you can restart a failed worker, log the error, and continue—the other processes keep running.

## Practice

**Problem:** You have 10 million job postings arriving in batches. Each batch needs validation (check salary_year_avg is positive, job_posted_date is recent, job_location is not null), enrichment (deduplicate by job_id), and storage. You want to parse and validate in parallel workers without one corrupted record halting the pipeline.

```python
from multiprocessing import Pool, Queue
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional
import logging

@dataclass
class JobPosting:
    job_id: int
    job_title_short: str
    salary_year_avg: Optional[float]
    job_work_from_home: bool
    job_posted_date: str
    job_location: str

def validate_job_posting(raw_record: dict) -> Optional[JobPosting]:
    """Validates a single record. Returns None if invalid. Worker process runs this."""
    try:
        salary = float(raw_record.get('salary_year_avg') or 0)
        if salary < 0:
            logging.warning(f"Negative salary in job_id {raw_record['job_id']}")
            return None
        
        posted_date = datetime.strptime(raw_record['job_posted_date'], '%Y-%m-%d')
        if posted_date < datetime.now() - timedelta(days=365):
            logging.warning(f"Stale posting: job_id {raw_record['job_id']}")
            return None
        
        location = str(raw_record.get('job_location', '')).strip()
        if not location:
            logging.warning(f"Missing location: job_id {raw_record['job_id']}")
            return None
        
        return JobPosting(
            job_id=int(raw_record['job_id']),
            job_title_short=str(raw_record['job_title_short']),
            salary_year_avg=salary if salary > 0 else None,
            job_work_from_home=bool(raw_record.get('job_work_from_home', False)),
            job_posted_date=posted_date.strftime('%Y-%m-%d'),
            job_location=location
        )
    except Exception as e:
        logging.error(f"Validation failed: {e}", exc_info=True)
        return None

def process_batch(raw_records: list[dict]) -> list[JobPosting]:
    """Use pool to validate batch in parallel. Main process orchestrates."""
    with Pool(processes=4) as pool:
        results = pool.map(validate_job_posting, raw_records)
    return [r for r in results if r is not None]

# Usage:
batches = [...]  # incoming data
for batch in batches:
    valid_postings = process_batch(batch)
    # Each worker ran in isolation; if one crashed, Pool restarts it
    # Main process unaffected by worker failures
    store_to_warehouse(valid_postings)
```

## Notes

- **Pickle overhead**: Serializing large DataFrames across process boundaries is slow. For big data, use `multiprocessing.shared_memory` or pass file paths, not the actual data.
- **Process spawning cost**: Creating a process is heavier than a thread. Use a Pool to reuse workers; don't spawn a new process per record.
- **Debugging is harder**: stack traces from crashed workers are harder to read; log aggressively, use `multiprocessing.get_logger()` instead of print.
- **Windows gotcha**: multiprocessing on Windows requires `if __name__ == '__main__':` guards; Unix forks but Windows spawns fresh interpreters.
- **Adjacent topics**: asyncio (for I/O-bound), threading (for I/O with shared state), and distributed computing (Ray, Dask) when you outgrow a single machine.
