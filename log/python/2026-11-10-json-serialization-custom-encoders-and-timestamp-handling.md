---
date: 2026-11-10
phase: python
topic: JSON serialization: custom encoders and timestamp handling
---

# JSON serialization: custom encoders and timestamp handling

*Python for data engineering*

## Concept

JSON serialization in Python requires custom handling when your objects contain types that the standard `json` module doesn't recognize—most commonly `datetime`, `date`, `Decimal`, and custom classes. Without a custom encoder, calling `json.dumps()` on a pipeline result containing a timestamp or non-standard type raises `TypeError`, forcing you to manually convert every field before serialization. This becomes a source of bugs in data pipelines: inconsistent date formats across outputs, silent failures in retry logic, and untestable code paths.

Custom encoders solve this by defining a subclass of `JSONEncoder` that specifies how to handle non-standard types. Timestamp handling is particularly critical in data engineering because timestamps are ubiquitous in fact tables, source systems often disagree on format (ISO 8601 vs Unix epoch vs custom strings), and incorrect serialization breaks downstream JSON-based APIs and message queues. By centralizing encoding logic in a reusable class, you make serialization explicit, testable, and resilient to bad input.

## Practice

**Problem:** You're building a pipeline that reads from `job_postings_fact`, filters records where `salary_year_avg > 100000`, and publishes results to a Kafka topic as JSON. The `job_posted_date` is a `datetime.date` object, and you need to serialize the entire record reliably without losing precision or breaking on edge cases (null salaries, missing dates).

```python
import json
from datetime import datetime, date
from decimal import Decimal
from typing import Any

class DataEngineeringEncoder(json.JSONEncoder):
    def default(self, obj: Any) -> Any:
        if isinstance(obj, (date, datetime)):
            return obj.isoformat()
        if isinstance(obj, Decimal):
            return float(obj)
        if obj is None:
            return None
        return super().default(obj)

# Pipeline code
records = [
    {
        "job_id": 1,
        "job_title_short": "Data Engineer",
        "salary_year_avg": Decimal("125000.50"),
        "job_work_from_home": True,
        "job_posted_date": date(2024, 1, 15),
        "job_location": "Remote"
    }
]

# Safe serialization with custom encoder
json_output = json.dumps(records, cls=DataEngineeringEncoder, default=str)
print(json_output)
# Output: [{"job_id": 1, ..., "salary_year_avg": 125000.5, "job_posted_date": "2024-01-15", ...}]
```

## Notes

- **Timestamp format matters downstream:** Always use ISO 8601 (`isoformat()`) unless the consuming system explicitly requires Unix epoch; it's human-readable and preserves timezone info if present.
- **Decimal vs float trade-off:** Converting `Decimal` to `float` loses precision for financial data; consider returning a string instead (`str(obj)`) if exact decimal representation is required by downstream systems.
- **Fails fast with `super().default(obj)`:** Don't use a blanket `default=str` encoder—it hides bugs. Explicitly handle known types and let unknown types raise `TypeError` so you catch serialization issues in tests, not production.
- **Test with None and edge cases:** Custom encoders should be tested with null values, empty dates, and missing fields to ensure idempotency and that retry logic doesn't corrupt data.
- **Connects to:** dataclass serialization (use `dataclasses.asdict()` + custom encoder), schema validation (Pydantic models with `.model_dump_json()`), and message queue contracts (Avro/Protobuf as alternatives to JSON for stricter typing).
