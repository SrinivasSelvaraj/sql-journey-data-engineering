---
date: 2026-09-13
phase: python
topic: Slots and object layout for performance
---

# Slots and object layout for performance

*Python for data engineering*

## Concept

Python stores instance attributes in a dictionary (`__dict__`) by default, which adds memory overhead and lookup latency—critical concerns when instantiating millions of objects in a data pipeline. Using `__slots__` pre-declares which attributes a class will have, replacing the dictionary with a fixed-size tuple-like structure. This reduces per-instance memory by 40–50% and speeds attribute access, especially important when building fact tables or event streams where you're creating thousands of row objects.

Without `__slots__`, each object carries the full dict machinery even if it only holds five simple fields. In memory-constrained ETL environments (cloud Spot instances, batch jobs with limited heap) or when deserializing millions of JSON records into objects, this overhead compounds. Unslotted classes also make it too easy to accidentally add new attributes at runtime, which is a silent source of bugs in production pipelines.

## Practice

**Problem:** You are loading job postings into a fact table. Each posting becomes an object for validation and transformation before insertion. With 2M records per day and minimal memory, you need to minimize the footprint of the staging objects.

```python
from dataclasses import dataclass
from datetime import date
from typing import Optional

@dataclass
class JobPosting:
    __slots__ = (
        'job_id', 'job_title_short', 'salary_year_avg', 
        'job_work_from_home', 'job_posted_date', 'job_location'
    )
    
    job_id: int
    job_title_short: str
    salary_year_avg: Optional[int]
    job_work_from_home: bool
    job_posted_date: date
    job_location: str
    
    def validate(self) -> bool:
        return (
            self.job_id > 0 and 
            len(self.job_title_short) > 0 and
            (self.salary_year_avg is None or self.salary_year_avg > 0)
        )
```

This cuts per-object memory use from ~296 bytes to ~152 bytes and prevents accidental attribute injection during pipeline stages.

## Notes

- **Slots + dataclass:** Use `@dataclass` for clean initialization; `__slots__` prevents the hidden `__dict__`. Together they're type-safe and compact.
- **Inheritance gotcha:** Subclasses inherit slots but must re-declare them; forgetting this re-adds `__dict__`. Only the leaf class's `__slots__` apply.
- **Serialization friction:** Some libraries (pickle, JSON) need special handling with slots; test round-trip serialization early in pipeline design.
- **Adjacent topics:** Object pooling, `array.array`, and pandas for bulk operations all pursue the same goal—reducing memory overhead at scale.
- **Revisit:** Profile your pipeline with `pympler.asizeof()` or `sys.getsizeof()` before and after to confirm gains; premature slotting on small datasets wastes clarity.
