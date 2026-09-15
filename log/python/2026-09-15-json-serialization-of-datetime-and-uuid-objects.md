---
date: 2026-09-15
phase: python
topic: JSON serialization of datetime and UUID objects
---

# JSON serialization of datetime and UUID objects

*Python for data engineering*

## Concept

JSON is the lingua franca of data pipelines—APIs return it, data lakes store it, logs aggregate it. But Python's `json` module has no built-in serializer for `datetime` and `UUID` objects, which are ubiquitous in data engineering: timestamps come from databases as datetime objects, IDs are often UUID type. Without explicit handling, `json.dumps()` raises `TypeError`, forcing your pipeline to crash or require manual conversion at call sites.

The fix is a custom `JSONEncoder` subclass or a `default` parameter that knows how to represent these types as JSON-safe primitives: `datetime` → ISO 8601 string, `UUID` → string. This is not optional busywork—it's the difference between a pipeline that handles production data cleanly and one scattered with ad-hoc `.isoformat()` calls that fail when someone passes a `date` instead of `datetime`.

A robust approach also validates on deserialization. Parse JSON back to typed objects (using `datetime.fromisoformat()`, `UUID()` constructor) rather than leaving strings in memory. This catches malformed data early and makes downstream code type-safe.

## Practice

**Problem:** You're writing a data ingestion function that reads job posting records and publishes them as JSON to a message queue. The `job_posted_date` column is a `date` object, and `job_id` is a `UUID`. Standard `json.dumps()` fails.

```python
import json
from datetime import datetime, date
from uuid import UUID
from typing import Any

class DataEngineerEncoder(json.JSONEncoder):
    """Custom encoder for common data types in pipelines."""
    def default(self, obj: Any) -> Any:
        if isinstance(obj, (datetime, date)):
            return obj.isoformat()
        if isinstance(obj, UUID):
            return str(obj)
        return super().default(obj)

# Usage
record = {
    "job_id": UUID("550e8400-e29b-41d4-a716-446655440000"),
    "job_title_short": "Data Engineer",
    "salary_year_avg": 120000,
    "job_work_from_home": True,
    "job_posted_date": date(2024, 1, 15),
    "job_location": "Remote"
}

# Serialize reliably
payload = json.dumps(record, cls=DataEngineerEncoder)

# Deserialize with type coercion
def deserialize_job_posting(data: dict) -> dict:
    data["job_posted_date"] = datetime.fromisoformat(data["job_posted_date"]).date()
    data["job_id"] = UUID(data["job_id"])
    return data
```

## Notes

- **Encoder vs. `default` param:** Using a custom `JSONEncoder` class is cleaner for pipelines—set it once, reuse everywhere. The `default=` function works too but is less visible.
- **ISO 8601 for datetime:** Always use `.isoformat()` or `datetime.fromisoformat()`. Avoid strftime/strptime unless you need a specific format; ISO 8601 is timezone-aware and sortable.
- **Round-trip safety:** Custom encoder is only half the battle. Deserializer must parse strings back to typed objects—don't leave UUIDs and dates as strings in memory or you lose type checking and validation.
- **Testing pressure:** Write tests that pass objects *and* malformed JSON (e.g., "2024-13-45", invalid UUID strings). A good encoder doesn't hide bad input; it should fail fast with clear messages.
- **Connects to:** Pydantic models (which handle serialization automatically), dataclass factories, API request/response validation, and logging serialization.
