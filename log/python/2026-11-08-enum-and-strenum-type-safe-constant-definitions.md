---
date: 2026-11-08
phase: python
topic: Enum and StrEnum: type-safe constant definitions
---

# Enum and StrEnum: type-safe constant definitions

*Python for data engineering*

## Concept

Enums and StrEnums provide type-safe, restricted sets of constant values. Instead of passing bare strings like `"remote"` or `"hybrid"` throughout your pipeline, you define them once in an Enum class and use the enum member. Python's type checker catches invalid values at dev time; runtime code raises an error if you try to assign an undefined member. This matters in data pipelines because job posting ETL code often reads categorical columns (work arrangement, job level, salary band) from messy sources—without enums, a typo like `"hybrd"` silently corrupts data. With enums, you validate and transform input early, making pipelines testable and self-documenting.

StrEnum (Python 3.11+) is a subclass of Enum where members are also strings, so they serialize cleanly to JSON and SQL without `.value`. Enum requires explicit `.value` access in string contexts. Neither prevents bad input alone—you still parse and validate—but they make validation code cleaner and let your type checker and IDE catch logic errors before testing.

## Practice

**Problem:** Your pipeline reads job posting CSVs with a `work_arrangement` column containing values like "Remote", "On-site", "Hybrid", and "Flexible". Some rows have typos ("Remot", "onsite"), and you need to standardize them, reject unknowns, and safely insert into `job_work_from_home` (boolean for remote-only) without silent data loss.

```python
from enum import StrEnum
from typing import Optional
import pandas as pd

class WorkArrangement(StrEnum):
    REMOTE = "remote"
    ON_SITE = "on_site"
    HYBRID = "hybrid"
    FLEXIBLE = "flexible"

def parse_work_arrangement(raw_value: str) -> Optional[WorkArrangement]:
    """Normalize and validate work arrangement; return None for unknowns."""
    normalized = raw_value.strip().lower().replace("-", "_")
    try:
        return WorkArrangement(normalized)
    except ValueError:
        return None

def transform_job_postings(df: pd.DataFrame) -> pd.DataFrame:
    """Parse, validate, and flag bad rows."""
    df["work_arrangement"] = df["work_arrangement"].apply(parse_work_arrangement)
    bad_rows = df["work_arrangement"].isna()
    if bad_rows.any():
        print(f"Warning: {bad_rows.sum()} rows with invalid work_arrangement")
    
    df["job_work_from_home"] = df["work_arrangement"].apply(
        lambda x: x == WorkArrangement.REMOTE if x else None
    )
    return df[~bad_rows]
```

## Notes

- **StrEnum vs. Enum:** Use `StrEnum` for data pipeline constants that will be serialized or compared to strings (job status, location region codes). Use `Enum` when you need to attach metadata or when members are not strings (status codes as integers). Always import from `enum`.

- **Validation timing:** Parse enums at the ingestion boundary (after reading CSV, before DB insert). This isolates bad data and makes error messages actionable. Pair with `.apply()` in pandas or a validation function in your data class.

- **Combines with dataclasses & Pydantic:** Define a `JobPosting` dataclass or Pydantic model with `work_arrangement: WorkArrangement` field; validation happens on instantiation. This scales to multi-column schemas and integrates with FastAPI for API-driven pipelines.

- **Testing:** Unit-test the parser function with a matrix of valid, edge-case (uppercase, hyphens), and invalid inputs. Type checkers catch assignments like `arr = WorkArrangement("bad")` but not `parse_work_arrangement(df.loc[i, col])` returning wrong type—use `assert isinstance()` in tests.

- **Serialization:** When writing to SQL or JSON, StrEnum members act as strings natively (no `.value`). For Enum, use `.value` or a custom serializer; Pydantic models handle this automatically with `model_dump()`.
