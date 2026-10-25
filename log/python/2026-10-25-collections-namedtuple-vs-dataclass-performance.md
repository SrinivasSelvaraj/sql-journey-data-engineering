---
date: 2026-10-25
phase: python
topic: Collections.namedtuple vs dataclass performance
---

# Collections.namedtuple vs dataclass performance

*Python for data engineering*

## Concept

`namedtuple` and `dataclass` both create structured, typed containers for data records, but they trade off mutability, memory footprint, and feature richness. `namedtuple` is immutable, lightweight (10–15% less memory), and hashable by default—ideal for cache keys or dict lookups in high-volume pipelines. `dataclass` is mutable, supports default values and post-init validation natively, and generates useful methods like `__repr__` and `__eq__` with less boilerplate. In data pipelines, this choice directly affects whether you can accidentally corrupt records mid-transformation, whether validation happens at construction or downstream, and whether your profiling budget gets consumed by object overhead. Pick `namedtuple` when records are immutable facts (events, snapshots, audit logs); pick `dataclass` when records are mutable work-in-progress (staging tables, ETL intermediate states).

## Practice

**Problem:** You're building a job posting ingestion pipeline. Raw API responses arrive with inconsistent schemas, missing dates, and salary strings like "$80k-$120k". You need to normalize them into a `job_postings_fact` structure and fail loudly on bad input rather than propagating nulls downstream.

```python
from dataclasses import dataclass
from datetime import date
import re

@dataclass
class JobPostingFact:
    job_id: int
    job_title_short: str
    salary_year_avg: float | None
    job_work_from_home: bool
    job_posted_date: date
    job_location: str

    def __post_init__(self):
        # Validate immutability after construction
        if not self.job_id or not isinstance(self.job_id, int):
            raise ValueError(f"job_id must be a non-zero int, got {self.job_id}")
        if not self.job_title_short or len(self.job_title_short.strip()) == 0:
            raise ValueError("job_title_short cannot be empty")
        if self.salary_year_avg is not None and self.salary_year_avg < 0:
            raise ValueError(f"salary_year_avg cannot be negative, got {self.salary_year_avg}")
        if not isinstance(self.job_posted_date, date):
            raise ValueError(f"job_posted_date must be a date object, got {type(self.job_posted_date)}")

# Usage in pipeline
def normalize_job_posting(raw_record: dict) -> JobPostingFact:
    salary_str = raw_record.get("salary_range", "")
    salary_avg = None
    if salary_str:
        match = re.search(r'\$(\d+)k?-\$(\d+)k?', salary_str)
        if match:
            low, high = int(match.group(1)) * 1000, int(match.group(2)) * 1000
            salary_avg = (low + high) / 2
    
    return JobPostingFact(
        job_id=raw_record["job_id"],
        job_title_short=raw_record["job_title"],
        salary_year_avg=salary_avg,
        job_work_from_home=raw_record.get("remote", False),
        job_posted_date=date.fromisoformat(raw_record["posted_date"]),
        job_location=raw_record["location"]
    )
```

## Notes

- **`__post_init__` is where validation lives**: use it to enforce invariants immediately after construction; bad data fails fast before entering the pipeline, not in a SQL `WHERE` clause three transforms later.
- **`frozen=True` on dataclass makes it immutable**: use this for records meant to be cached or used as dict keys; it prevents accidental mutation and enables hashing.
- **`namedtuple` + `typing.NamedTuple`**: the latter supports type hints and is the modern standard; plain `collections.namedtuple` lacks IDE support and is now rarely worth choosing over `dataclass`.
- **Memory and speed matter at scale**: `namedtuple` is ~8 bytes lighter per instance; at 10M records, that's 80MB saved. Profile your actual pipeline before optimizing; in most cases the validation and I/O overhead dominate.
- **Adjacent to schema validation**: consider `pydantic.BaseModel` if you need JSON serialization, automatic coercion, or complex nested schemas; it's heavier but catches more input errors automatically.
