---
date: 2026-10-08
phase: python
topic: JSON serialization: custom encoders and datetime handling
---

# JSON serialization: custom encoders and datetime handling

*Python for data engineering*

## Concept

JSON serialization in Python becomes critical in data pipelines when you need to convert objects—especially those with non-primitive types like `datetime`, `Decimal`, or custom classes—into JSON strings for APIs, logs, or file storage. Without custom encoders, `json.dumps()` fails immediately on these types, crashing your pipeline or forcing you to manually convert every object beforehand, which is error-prone and scattered across your code.

The standard approach is to subclass `json.JSONEncoder` and override the `default()` method to handle your specific types. For datetime objects, the typical pattern is to convert them to ISO 8601 strings (`isoformat()`), which are both human-readable and unambiguous. This matters in data engineering because job posting records often contain posted dates, application deadlines, or metadata timestamps that must survive serialization without data loss or type confusion.

Without this discipline, your pipeline either crashes unpredictably when encountering datetimes, or you end up with string-encoded datetimes in inconsistent formats scattered throughout your codebase. A custom encoder centralizes the logic and makes your serialization behavior explicit and testable.

## Practice

**Problem:** You're building a data pipeline that reads `job_postings_fact` records and writes them to a JSON file for downstream consumers. The `job_posted_date` column is a DATE type (Python `datetime.date` object after reading from a database). Standard `json.dumps()` will fail.

```python
import json
from datetime import datetime, date
from decimal import Decimal

class DataEngineeringEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, (date, datetime)):
            return obj.isoformat()
        if isinstance(obj, Decimal):
            return float(obj)
        return super().default(obj)

# Usage in your pipeline
job_record = {
    'job_id': 1,
    'job_title_short': 'Data Engineer',
    'salary_year_avg': Decimal('120000.50'),
    'job_work_from_home': True,
    'job_posted_date': date(2024, 1, 15),
    'job_location': 'Remote'
}

json_output = json.dumps(job_record, cls=DataEngineeringEncoder)
print(json_output)
# Output: {"job_id": 1, "job_title_short": "Data Engineer", "salary_year_avg": 120000.5, "job_work_from_home": true, "job_posted_date": "2024-01-15", "job_location": "Remote"}
```

## Notes

- **Mistake: Catching all exceptions.** Don't wrap `json.dumps()` in a broad try-except; instead, fail fast with a clear error message so you discover type mismatches during testing, not in production.
- **ISO 8601 is your friend.** Always use `.isoformat()` for dates/datetimes; it's reversible with `datetime.fromisoformat()` and language-agnostic, unlike custom string formats.
- **Decimal vs. float trade-off.** Converting `Decimal` to `float` loses precision; for financial data, consider serializing to string instead and documenting the choice.
- **Connects to:** type hints (annotate your encoder expectations), custom dataclasses (make your records explicit types, not dicts), and deserialization (write a matching decoder to round-trip safely).
- **Revisit:** This pattern scales to `__dict__` on custom objects (`if hasattr(obj, '__dict__'): return obj.__dict__`) but only if you also version your schema for backward compatibility.
