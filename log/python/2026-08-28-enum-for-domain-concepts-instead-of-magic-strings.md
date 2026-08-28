---
date: 2026-08-28
phase: python
topic: Enum for domain concepts instead of magic strings
---

# Enum for domain concepts instead of magic strings

*Python for data engineering*

## Concept

Magic strings—hardcoded values like `"remote"`, `"hybrid"`, `"onsite"`—scatter validation logic across your codebase and make refactoring fragile. When a business requirement changes (e.g., `"remote"` becomes `"work_from_home"`), you must hunt through every file to update strings. Enums centralize these domain concepts as first-class Python objects, making the type system enforce valid values at development and runtime.

This matters most in data pipelines where bad input silently corrupts datasets. If you accept any string for work location, a typo like `"remot"` passes validation and pollutes your fact table. With an Enum, that typo fails immediately with a clear error, catching bugs before they reach production. Enums also self-document code: reading `WorkLocation.REMOTE` tells you exactly what values are legal, whereas a comment next to a string does not.

## Practice

**Problem:** The pipeline ingests job postings with a `job_work_from_home` boolean, but the raw data arrives as location strings (`"Remote"`, `"Hybrid"`, `"On-site"`). You need to normalize these strings, reject invalid values, and make the mapping explicit and testable.

```python
from enum import Enum

class WorkLocation(Enum):
    REMOTE = "remote"
    HYBRID = "hybrid"
    ONSITE = "onsite"

def parse_work_location(raw_value: str) -> WorkLocation:
    """Normalize and validate work location from raw input."""
    normalized = raw_value.strip().lower()
    try:
        return WorkLocation(normalized)
    except ValueError:
        raise ValueError(f"Invalid work location: '{raw_value}'. Must be one of {[e.value for e in WorkLocation]}")

def is_work_from_home(location: WorkLocation) -> bool:
    """Map work location to boolean for fact table."""
    return location in (WorkLocation.REMOTE, WorkLocation.HYBRID)

# Usage in pipeline:
for row in raw_data:
    location = parse_work_location(row["location"])
    job_postings_fact.insert({
        "job_id": row["job_id"],
        "job_work_from_home": is_work_from_home(location),
        ...
    })
```

## Notes

- **Avoid string comparisons after parsing**: Once you have an Enum, use it in conditionals (`if location == WorkLocation.REMOTE`) instead of re-checking the string value. This preserves type safety throughout the pipeline.
- **Enum is not just for storage**: Use Enum during validation and transformation, not only when inserting into the database. This catches errors early and makes unit tests more readable.
- **Pair with dataclasses or Pydantic**: Combine Enums with type-checked schemas (`pydantic.BaseModel`) to validate entire records, not just individual fields.
- **Document the Enum's enum values, not the Enum name**: The `.value` attribute holds the actual string/int; the Enum name is for code. Comment what each name represents in the business domain.
- **Connect to schema validation**: This pattern is the foundation for schema versioning and contract testing—ensure upstream and downstream agree on what values are legal before data touches your warehouse.
