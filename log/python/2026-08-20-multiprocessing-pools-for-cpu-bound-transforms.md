---
date: 2026-08-20
phase: python
topic: Multiprocessing pools for CPU-bound transforms
---

# Multiprocessing pools for CPU-bound transforms

*Python for data engineering*

## Concept

Multiprocessing pools distribute CPU-bound work across multiple processes, bypassing Python's GIL (Global Interpreter Lock) that prevents true parallelism in threads. In data pipelines, this matters when you transform millions of records with expensive operations: parsing complex strings, running regex, computing statistics, or applying ML models. Without pools, a pipeline that could run in 2 minutes serial takes 2 minutes anyway—because the GIL serializes CPU work even across threads. Pools shine when your bottleneck is computation, not I/O; if you're network-bound or disk-bound, async I/O or threaded I/O pools are better choices.

The critical failure mode is misidentifying the bottleneck. Wrapping a network call in `pool.map()` adds overhead and makes things slower. Similarly, pools require pickling data between processes, which has cost—if your transform is trivial (e.g., `x + 1`), serialization overhead dominates. Type hints and input validation become essential at scale because a crash in a worker process can silently fail or lock up the pool, making bugs hard to trace.

## Practice

**Problem:** You need to parse complex job descriptions from `job_postings_fact` and extract required years of experience (a regex-heavy operation on 2M rows). Serial execution takes 8 minutes; you have 8 CPU cores available.

```python
import re
from multiprocessing import Pool
from typing import Optional
from dataclasses import dataclass

@dataclass
class JobPosting:
    job_id: int
    job_title_short: str
    salary_year_avg: Optional[float]
    job_location: str
    years_required: Optional[int] = None

def extract_years_required(posting: JobPosting) -> JobPosting:
    """Extract years of experience from job title and description.
    
    Raises ValueError if posting is malformed.
    """
    if not posting or not isinstance(posting.job_title_short, str):
        raise ValueError(f"Invalid posting: {posting}")
    
    patterns = [
        r'(\d+)\+?\s*years?',
        r'(\d+)\s*years?\s*of',
    ]
    
    for pattern in patterns:
        match = re.search(pattern, posting.job_title_short, re.IGNORECASE)
        if match:
            posting.years_required = int(match.group(1))
            return posting
    
    posting.years_required = None
    return posting

# Usage
if __name__ == "__main__":
    postings = [
        JobPosting(1, "Senior Engineer, 5+ years required", 120000.0, "NYC"),
        JobPosting(2, "Analyst", 85000.0, "Remote"),
    ]
    
    with Pool(processes=8) as pool:
        results = pool.map(extract_years_required, postings, chunksize=5000)
    
    for result in results:
        print(f"{result.job_id}: {result.years_required} years")
```

## Notes

- **Pickling overhead is real**: only use multiprocessing for transforms taking >10ms per item; for faster operations, the serialization cost kills gains. Profile with `cProfile` first.
- **Chunksize tuning matters**: large chunks (5000–10000) reduce inter-process overhead but increase tail latency; start with `chunksize=len(data)//num_processes//4` and measure.
- **Error handling is invisible**: exceptions in worker processes often fail silently or hang the main process. Always wrap workers in try/except and log; consider `pool.imap_unordered()` with timeouts for early detection.
- **Connects to**: async I/O for I/O-bound work, dataframe `.apply(func, raw=True)` for vectorized alternatives in pandas, and Dask/Ray for distributed computing at scale.
- **Revisit when**: moving to streaming (Kafka), scaling beyond one machine (Spark), or switching languages (Rust for hot loops beats multiprocessing).
