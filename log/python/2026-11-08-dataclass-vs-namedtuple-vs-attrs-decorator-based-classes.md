---
date: 2026-11-08
phase: python
topic: Dataclass vs NamedTuple vs attrs: decorator-based classes
---

# Dataclass vs NamedTuple vs attrs: decorator-based classes

*Python for data engineering*

## Concept

In data pipelines, you often need lightweight classes to represent structured records—job postings, API responses, database rows—without the boilerplate of full OOP. Three Python tools compete here: **dataclasses** (Python 3.7+, mutable by default), **NamedTuple** (immutable, faster, tuple-like), and **attrs** (most flexible, third-party). Dataclasses are type-hinted and serialization-friendly (work well with `json`, `dataclass_asdict()`). NamedTuples are hashable and memory-efficient, making them ideal for deduplication and use as dictionary keys. attrs offers validators, converters, and slots for production robustness.

The choice matters in pipelines because bad input kills silently. A mutable dataclass can be modified mid-pipeline, hiding bugs. A NamedTuple prevents accidental mutation but lacks built-in validation. attrs lets you attach validators to catch malformed salary strings or invalid dates *at instantiation*, failing fast. For test doubles, immutability (NamedTuple, attrs frozen) makes assertions reliable; for ETL staging, dataclass flexibility speeds prototyping.

Without this structure, you pipeline data as raw tuples or dicts—no schema enforcement, typos go unnoticed, IDE autocomplete fails, and serialization requires manual wrangling. Typed classes are your first defense against downstream crashes.

## Practice

**Problem:** You receive job posting records as JSON from an API. Some have missing `job_location`, some have `salary_year_avg` as strings ("100000") or null, and `job_posted_date` comes as ISO strings. You need a class that validates on load, prevents accidental mutation, and exports cleanly to CSV.

```python
from dataclasses import dataclass
from datetime import date
from typing import Optional

@dataclass(frozen=True)
class JobPosting:
    job_id: int
    job_title_short: str
    salary_year_avg: Optional[int]
    job_work_from_home: bool
    job_posted_date: date
    job_location: str
    
    def __post_init__(self):
        # Validate after instantiation (frozen fields use object.__setattr__)
        if self.salary_year_avg is not None and self.salary_year_avg < 0:
            raise ValueError(f"Negative salary: {self.salary_year_avg}")
        if not self.job_title_short.strip():
            raise ValueError("job_title_short cannot be empty")

# In your pipeline:
raw_record = {
    "job_id": 1,
    "job_title_short": "Data Engineer",
    "salary_year_avg": "120000",  # string input
    "job_work_from_home": True,
    "job_posted_date": "2024-01-15",
    "job_location": "Remote"
}

# Parse and validate in one step:
posting = JobPosting(
    job_id=raw_record["job_id"],
    job_title_short=raw_record["job_title_short"],
    salary_year_avg=int(raw_record["salary_year_avg"]) if raw_record["salary_year_avg"] else None,
    job_work_from_home=raw_record["job_work_from_home"],
    job_posted_date=date.fromisoformat(raw_record["job_posted_date"]),
    job_location=raw_record["job_location"]
)
# If salary_year_avg was -5000, __post_init__ raises ValueError before the record enters your DB.
```

## Notes

- **Dataclass mutation trap:** `frozen=True` prevents accidental changes but serializers like `dataclasses.asdict()` still work. Without it, a function modifying `posting.salary_year_avg` silently corrupts your batch.
- **NamedTuple for dedup:** Use when you need to deduplicate records mid-pipeline (set membership, dict keys). Immutability + hashability = reliable grouping. Dataclasses are hashable only if frozen *and* all fields are hashable.
- **attrs for validators:** If you need conditional logic (e.g., "if remote then location must be blank"), attrs' `@validators` decorator scales better than `__post_init__`. Third-party cost worth it for strict schemas.
- **Serialization chain:** Frozen dataclass → `dataclasses.asdict()` → `json.dumps()` → database INSERT. Each step must handle Optional types and date conversion. Test this path early.
- **Type hints + mypy:** A typed class is dead weight without static checking. Run `mypy` on your pipeline; it catches `JobPosting(job_id="oops")` before production.
