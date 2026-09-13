---
date: 2026-09-13
phase: python
topic: Coverage thresholds and branch coverage enforcement
---

# Coverage thresholds and branch coverage enforcement

*Python for data engineering*

## Concept

Coverage thresholds define minimum percentages of code and branches that automated tests must exercise before a build passes. In data pipelines, hitting 80–90% code coverage catches missing error handlers, untested transformation logic, and edge cases in schema validation—gaps that silently corrupt data in production. Branch coverage goes deeper: it ensures both the "happy path" and exception handlers (if/else, try/except) are actually tested, not just declared.

Without enforced thresholds, developers skip testing conditional logic that runs only on bad input—malformed JSON, null columns, out-of-range dates. A pipeline that transforms 99% of rows correctly but fails silently on 1% of edge cases is a data quality disaster. Coverage enforcement makes the cost of untested code visible early: a PR won't merge if a new error handler or validation branch is dark (untested).

Set thresholds high enough to matter (80%+) but not so high that tests become busywork. Pair coverage checks with meaningful assertions: 100% coverage of nonsense tests is worse than 75% coverage of tests that verify actual invariants.

## Practice

**Problem:** The `job_postings_fact` table receives daily feeds with occasional null salaries, missing dates, and location strings with unexpected formatting. Your ETL extracts salary ranges and validates dates. Write testable code with branch coverage in mind.

```python
from datetime import datetime
from typing import Optional
import pytest

def parse_and_validate_salary(salary_year_avg: Optional[float]) -> Optional[float]:
    """Extract salary or return None; raise on invalid type."""
    if salary_year_avg is None:
        return None
    if not isinstance(salary_year_avg, (int, float)):
        raise ValueError(f"Expected numeric salary, got {type(salary_year_avg)}")
    if salary_year_avg < 0:
        raise ValueError(f"Salary cannot be negative: {salary_year_avg}")
    return float(salary_year_avg)

def parse_job_posted_date(date_str: Optional[str]) -> Optional[datetime]:
    """Parse ISO date or return None; raise on parse failure."""
    if date_str is None or date_str.strip() == "":
        return None
    try:
        return datetime.fromisoformat(date_str.split("T")[0])
    except (ValueError, AttributeError) as e:
        raise ValueError(f"Cannot parse date '{date_str}': {e}")

# Branch coverage: test happy path, None input, invalid type, boundary, and exception
def test_parse_salary_valid():
    assert parse_and_validate_salary(50000) == 50000.0

def test_parse_salary_none():
    assert parse_and_validate_salary(None) is None

def test_parse_salary_invalid_type():
    with pytest.raises(ValueError, match="Expected numeric"):
        parse_and_validate_salary("50000")

def test_parse_salary_negative():
    with pytest.raises(ValueError, match="cannot be negative"):
        parse_and_validate_salary(-10000)

def test_parse_date_valid():
    assert parse_job_posted_date("2024-01-15") == datetime(2024, 1, 15)

def test_parse_date_none():
    assert parse_job_posted_date(None) is None

def test_parse_date_empty():
    assert parse_job_posted_date("") is None

def test_parse_date_invalid():
    with pytest.raises(ValueError, match="Cannot parse date"):
        parse_job_posted_date("15-01-2024")
```

## Notes

- **Threshold trap:** Aiming for 100% coverage invites ghost tests that pass without assertions. Measure *meaningful* coverage: lines that make decisions, error paths that users hit, not every logging statement.
- **Branch vs. line:** A single `if x and y:` line can hide four branches. Branch coverage forces tests of `(True, True)`, `(True, False)`, `(False, True)`, `(False, False)`.
- **CI enforcement:** Use `pytest-cov` with `--cov-fail-under=85` in your CI/CD pipeline; fail the build visibly rather than hoping developers check coverage locally.
- **Null handling is critical:** In data pipelines, None/null branching accounts for ~30% of subtle bugs. Prioritize branch coverage of nullable fields over other conditional logic.
- **Revisit when refactoring:** Coverage reports highlight dead code; if a branch stays untested after two refactors, it may be unnecessary—delete it rather than writing brittle tests to hit it.
