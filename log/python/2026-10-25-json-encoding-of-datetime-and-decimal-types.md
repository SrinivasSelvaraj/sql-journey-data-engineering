---
date: 2026-10-25
phase: python
topic: Json encoding of datetime and decimal types
---

# Json encoding of datetime and decimal types

*Python for data engineering*

## Concept

JSON has no native datetime or decimal types, only strings and numbers. When you serialize Python `datetime` or `Decimal` objects to JSON without explicit handling, you get a `TypeError`. This matters because data pipelines often output to JSON for APIs, logs, or messaging queues—and datetime/decimal are ubiquitous in analytics (timestamps, precise monetary amounts, measurements).

The standard fix is a custom `JSONEncoder` subclass that converts these types to JSON-safe representations. `datetime` → ISO 8601 string, `Decimal` → string (to avoid float precision loss) or float (if acceptable). Without this, your pipeline crashes at serialization time, or silently loses precision if you're not careful.

This is not optional in production: financial data, event timestamps, and audit logs all depend on correct serialization. A misconfigured encoder can corrupt data downstream or cause deserialization to fail in consuming systems.

## Practice

**Problem:** Load `job_postings_fact` into a JSON file for API consumption. Job salaries use `Decimal` for precision, and `job_posted_date` is a SQL DATE. Your pipeline must preserve both exactly.

```python
import json
from datetime import date
from decimal import Decimal
from typing import Any

class DataEngineeringEncoder(json.JSONEncoder):
    def default(self, obj: Any) -> Any:
        if isinstance(obj, Decimal):
            # Keep as string to preserve precision (no float rounding)
            return str(obj)
        if isinstance(obj, date):
            # ISO 8601: YYYY-MM-DD
            return obj.isoformat()
        return super().default(obj)

# Usage in pipeline
job_postings = [
    {
        "job_id": 1,
        "job_title_short": "Data Engineer",
        "salary_year_avg": Decimal("125000.50"),
        "job_work_from_home": True,
        "job_posted_date": date(2024, 1, 15),
        "job_location": "New York, NY"
    }
]

with open("job_postings.json", "w") as f:
    json.dump(job_postings, f, cls=DataEngineeringEncoder, indent=2)
```

## Notes

- **Decimal → string vs. float trade-off:** Use string for money/precise values; use float only if you control downstream parsing and precision loss is acceptable. Always document your choice.
- **Datetime variants:** `datetime.datetime`, `datetime.date`, and `datetime.time` each need handling. Prefer ISO 8601 strings for cross-system compatibility.
- **Testing is critical:** Write tests that round-trip JSON (serialize → deserialize) and assert the output type and value match the input. Precision loss is easy to miss.
- **Related topics:** `json.loads()` with custom decoders, `dataclasses.asdict()` before JSON encoding, timezone-aware datetimes (use `.isoformat()` for UTC).
- **Common mistake:** Using `str(obj)` without a custom encoder—Python will raise `TypeError` on first `Decimal` or `datetime` object, stopping the pipeline mid-run.
