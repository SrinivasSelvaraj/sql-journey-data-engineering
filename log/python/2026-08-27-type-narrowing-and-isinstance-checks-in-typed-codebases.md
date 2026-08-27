---
date: 2026-08-27
phase: python
topic: Type narrowing and isinstance checks in typed codebases
---

# Type narrowing and isinstance checks in typed codebases

*Python for data engineering*

## Concept

Type narrowing is the process of refining a variable's type from a broader category to a more specific one within a conditional block. In Python data pipelines, you often receive data with `Any` type, `Union` types, or optional values (`None`), and you need to guarantee to both the type checker and your runtime that a value is safe to use before accessing attributes or methods. `isinstance()` checks are the idiomatic way to narrow types—they satisfy both mypy/pyright and protect against malformed input.

Without type narrowing, you either suppress type errors (hiding real bugs), panic-catch all exceptions (masking the root cause), or crash on unexpected data shapes in production. When loading job postings from an external API, you might receive `salary_year_avg` as a string, float, or `None`. Without narrowing, you can't confidently parse it; with narrowing, your code is explicit, testable, and auditable.

## Practice

**Problem:** A data pipeline ingests job posting records where `salary_year_avg` arrives as `Union[str, float, None]`. You need to clean it into a single `float` column for the warehouse, handling empty strings, "N/A", out-of-range values, and missing data gracefully.

```sql
-- Target fact table
CREATE TABLE job_postings_fact (
    job_id INT PRIMARY KEY,
    job_title_short VARCHAR(100),
    salary_year_avg FLOAT NULL,
    job_work_from_home BOOLEAN,
    job_posted_date DATE,
    job_location VARCHAR(100)
);

-- Python extraction + type narrowing
def parse_salary(raw_value: Union[str, float, None]) -> Optional[float]:
    """Narrow and validate salary input before warehouse insert."""
    
    # Narrow None early
    if raw_value is None:
        return None
    
    # Narrow to string, handle text cases
    if isinstance(raw_value, str):
        cleaned = raw_value.strip().upper()
        if cleaned in ("", "N/A", "UNKNOWN"):
            return None
        try:
            parsed = float(cleaned)
        except ValueError:
            logger.warning(f"Could not parse salary string: {raw_value}")
            return None
    # Narrow to numeric type
    elif isinstance(raw_value, (int, float)):
        parsed = float(raw_value)
    else:
        logger.error(f"Unexpected salary type {type(raw_value)}: {raw_value}")
        return None
    
    # Final validation after narrowing
    if parsed < 0 or parsed > 500_000:
        logger.warning(f"Salary {parsed} outside acceptable range")
        return None
    
    return parsed

# Usage in pipeline
def load_job_postings(records: List[Dict[str, Any]]) -> List[Dict]:
    """Type-narrowed transformation before INSERT."""
    cleaned = []
    for record in records:
        record["salary_year_avg"] = parse_salary(record.get("salary_year_avg"))
        cleaned.append(record)
    return cleaned
```

## Notes

- **Narrowing order matters:** check `None` first (short-circuit), then string edge cases, then numeric. Mypy tracks your branches—if you narrow in the wrong order, it won't trust your narrowing.
- **`isinstance()` vs `type()` checks:** always use `isinstance()` for inheritance and duck-typing; `type()` is brittle and mypy doesn't narrow as reliably.
- **Logging at narrowing points:** each `isinstance` branch is a decision fork where data quality issues surface. Log what you're dropping; use those logs to tune parsing logic.
- **Adjacent skills:** exception handling (`try/except` after narrowing), schema validation (pydantic models do this automatically), and structured logging for audit trails in production pipelines.
- **Revisit:** consider adding a `Literal` type (e.g., `Literal["valid", "missing", "out_of_range"]`) to track rejection reason downstream, enabling analytics on data quality per source.
