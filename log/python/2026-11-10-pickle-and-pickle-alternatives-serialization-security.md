---
date: 2026-11-10
phase: python
topic: Pickle and pickle alternatives: serialization security
---

# Pickle and pickle alternatives: serialization security

*Python for data engineering*

## Concept

Pickle is Python's native serialization format, but it executes arbitrary code during deserialization, making it a critical security risk when loading untrusted data. In data pipelines, you often receive serialized objects from APIs, message queues, caches, or upstream jobs—any of which could be compromised. An attacker can embed malicious Python code in a pickled object that runs automatically when you unpickle it, giving them full system access.

Safe alternatives exist: JSON for structured data, Protocol Buffers or MessagePack for binary efficiency, and Parquet for columnar analytics data. The choice depends on your data shape and trust boundary. For pipeline code, the rule is simple: never unpickle data from external sources, and never expose pickle endpoints in APIs. If you must serialize internal objects (configs, cached models), use pickle only between processes you control completely, and validate the source.

This matters most in production because deserialization is usually invisible—it happens in imports, job initialization, or cache hits. A developer who adds `pickle.load(open(model_file))` without checking the model's origin can silently introduce a supply-chain attack into your entire warehouse.

## Practice

**Problem:** A data pipeline receives job posting updates from an external vendor via a pickled Python dict object. Build a safe ingestion layer that validates and loads this data into the `job_postings_fact` table.

```python
import json
import pickle
from typing import TypedDict
from datetime import date
import logging

logger = logging.getLogger(__name__)

class JobPosting(TypedDict):
    job_id: int
    job_title_short: str
    salary_year_avg: int
    job_work_from_home: bool
    job_posted_date: date
    job_location: str

def load_job_postings_safe(data_path: str, use_pickle: bool = False) -> list[JobPosting]:
    """
    Load job postings from JSON (safe) or reject pickle (unsafe).
    """
    if use_pickle:
        logger.warning("Pickle requested—rejecting for security. Use JSON instead.")
        raise ValueError("Pickle deserialization disabled. Provide JSON data.")
    
    try:
        with open(data_path, 'r') as f:
            raw_data = json.load(f)
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON: {e}")
        raise
    
    postings = []
    for item in raw_data:
        try:
            posting = JobPosting(
                job_id=int(item['job_id']),
                job_title_short=str(item['job_title_short'])[:100],
                salary_year_avg=int(item['salary_year_avg']),
                job_work_from_home=bool(item['job_work_from_home']),
                job_posted_date=date.fromisoformat(item['job_posted_date']),
                job_location=str(item['job_location'])[:200]
            )
            postings.append(posting)
        except (KeyError, ValueError, TypeError) as e:
            logger.error(f"Validation failed for record {item.get('job_id')}: {e}")
            raise
    
    return postings
```

## Notes

- **Never pickle untrusted data.** If a vendor sends pickled files, ask for JSON, CSV, or Parquet instead. Pickle is only safe between processes under your control.
- **Validation is not enough.** Even after unpickling safely, you must validate *schema* (type-check every field) and *values* (ranges, nulls, formats). The TypedDict approach above documents the contract.
- **Message queues and caches are trust boundaries.** If your Redis cache or Kafka topic could be read by an attacker, don't use pickle. Use JSON or a serialization library with a whitelist (e.g., `jsonpickle` with restrict_to_safe_types).
- **Connected to supply-chain security and secrets management.** Unsafe deserialization is how compromised ML models or config files silently execute backdoors. Always hash and sign serialized objects in production, or audit the source.
- **Revisit dataclass vs TypedDict.** For more complex validation, consider Pydantic models instead of plain TypedDict—they enforce types at construction time and give you `.dict()` / `.json()` for safe re-serialization.
