---
date: 2026-08-28
phase: python
topic: Parameterized tests with pytest.mark.parametrize
---

# Parameterized tests with pytest.mark.parametrize

*Python for data engineering*

## Concept

`pytest.mark.parametrize` lets you run the same test function multiple times with different input values, eliminating copy-paste test code. Instead of writing ten nearly-identical test functions to validate edge cases, you write one test and pass it a list of (input, expected_output) tuples. This is critical for data pipelines because your transformations must handle many classes of bad input—NULL values, empty strings, out-of-range dates, type mismatches—and you need evidence that each case is handled correctly.

Without parameterized tests, you either skip edge cases (dangerous) or maintain duplicate test code that diverges as your logic evolves. Parameterized tests make it obvious which scenarios you've covered. For example, testing a salary validation function against `[None, 0, -5000, 999999999, "invalid"]` as a single parameterized test is more maintainable than five separate `test_salary_*` functions.

This pattern becomes essential in data pipelines where transformation logic must gracefully handle real-world messiness. A single parameterized test can document and verify your pipeline's contract: "given these inputs, produce these outputs or raise this specific error."

## Practice

**Problem:** The `job_postings_fact` table receives salary data from multiple sources with inconsistent formatting. You need a function `normalize_salary(raw_salary: str | None) -> float | None` that converts `"120k"`, `"120000"`, `" $120,000 "`, and invalid strings into a normalized yearly float or None, raising `ValueError` only for strings that are clearly attempts to provide data (not None/empty). Write a parameterized test that proves the function handles all cases.

```python
import pytest

def normalize_salary(raw_salary: str | None) -> float | None:
    if raw_salary is None or raw_salary.strip() == "":
        return None
    cleaned = raw_salary.strip().replace("$", "").replace(",", "").lower()
    if cleaned.endswith("k"):
        return float(cleaned[:-1]) * 1000
    try:
        return float(cleaned)
    except ValueError:
        raise ValueError(f"Cannot parse salary: {raw_salary}")

@pytest.mark.parametrize("raw_input,expected_output", [
    (None, None),
    ("", None),
    ("  ", None),
    ("120k", 120000.0),
    ("120K", 120000.0),
    ("$120,000", 120000.0),
    (" $120,000 ", 120000.0),
    ("120000", 120000.0),
    ("120000.50", 120000.50),
])
def test_normalize_salary_valid(raw_input, expected_output):
    assert normalize_salary(raw_input) == expected_output

@pytest.mark.parametrize("raw_input", [
    "not a number",
    "120x",
    "ABC",
])
def test_normalize_salary_invalid(raw_input):
    with pytest.raises(ValueError):
        normalize_salary(raw_input)
```

## Notes

- **Parametrize before implementing:** Write your parameter list first to define the contract. This forces you to think through edge cases before coding the function.
- **Separate valid and invalid cases:** Use two `@pytest.mark.parametrize` decorators—one for expected successes, one for error cases with `pytest.raises()`. Keeps your test intent clear.
- **Ids for readability:** Add `ids=` parameter to label each test case: `@pytest.mark.parametrize("x,y", [(1,2), (3,4)], ids=["small", "large"])`. Makes failure output readable.
- **Connects to:** Type hints (validate input types), exception handling (test error paths), and property-based testing (hypothesis library for auto-generating edge cases).
- **Revisit:** When your pipeline fails in production on an unexpected input, add that input to your parametrize list immediately. Your tests become a living catalog of real-world edge cases.
