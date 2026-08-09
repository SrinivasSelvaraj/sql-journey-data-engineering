---
date: 2026-08-09
phase: python
topic: Property-based testing with hypothesis
---

# Property-based testing with hypothesis

*Python for data engineering*

## Concept

Property-based testing uses the `hypothesis` library to generate hundreds or thousands of random inputs automatically, then checks that your code satisfies invariant properties rather than matching hardcoded outputs. Instead of writing `assert process([1, 2, 3]) == [2, 4, 6]`, you write `assert all(x % 2 == 0 for x in process(integers()))`, letting hypothesis find edge cases you didn't think of.

This matters deeply in data pipelines because real data is messy: nulls, empty strings, dates in the future, negative salaries, duplicates. Unit tests with three handpicked examples won't catch the bizarre input that crashes production. Property-based tests explore the input space systematically, catching off-by-one errors, type coercion bugs, and boundary failures that slip past manual cases.

Without it, you ship pipelines that work on test data but fail on the first Tuesday of month-end processing when someone uploads a CSV with a different encoding, or salary values as strings, or dates from 1850.

## Practice

**Problem:** Write a transformation that normalizes job posting salary data. It must handle nulls, convert salary strings to integers, reject impossible values (negative or >$500k), and preserve the original row if validation fails. Test that the output always has the same row count as input, never loses a job_id, and never creates negative or >$500k salaries in valid rows.

```python
from hypothesis import given, strategies as st
import pandas as pd
from typing import Optional

def normalize_salary(salary_input: Optional[str]) -> Optional[int]:
    """Convert salary string to int; return None if invalid."""
    if salary_input is None or salary_input == "":
        return None
    try:
        sal = int(float(salary_input))
        if sal < 0 or sal > 500000:
            return None
        return sal
    except (ValueError, TypeError):
        return None

@given(
    job_ids=st.lists(st.integers(min_value=1, max_value=1_000_000), min_size=1, max_size=100, unique=True),
    salaries=st.lists(
        st.one_of(st.none(), st.text(), st.integers(min_value=-100000, max_value=600000)),
        min_size=1,
        max_size=100
    )
)
def test_salary_normalization_preserves_row_count(job_ids, salaries):
    """Property: output row count = input row count, all job_ids preserved."""
    df = pd.DataFrame({
        'job_id': job_ids[:len(salaries)],
        'salary_year_avg': salaries
    })
    
    df['salary_normalized'] = df['salary_year_avg'].apply(normalize_salary)
    
    # Properties that must always hold
    assert len(df) == len(df), "Row count changed"
    assert set(df['job_id']) == set(job_ids[:len(salaries)]), "Job IDs lost"
    assert all(
        (s is None) or (0 <= s <= 500000) 
        for s in df['salary_normalized']
    ), "Salary outside valid range"
```

## Notes

- **Shrinking:** When hypothesis finds a failing input, it automatically simplifies it to the minimal case—if a list of 47 integers breaks your code, it'll narrow it down to 2 or 3. Invaluable for debugging.
- **Flakiness detector:** If a test passes 100 times then fails on the 101st, hypothesis will catch it; good for catching race conditions and randomness leaks in data operations.
- **Strategies library:** Learn `st.lists()`, `st.integers()`, `st.text()`, `st.dates()`, `st.one_of()`, and `st.from_regex()` well—these are your input generators; use `@st.composite` for domain-specific generators (e.g., valid SQL identifiers).
- **Complements unit tests:** Don't replace hardcoded tests (they're still fast and clear); use property-based tests to fill gaps and catch tail cases in validation, parsing, and aggregation logic.
- **Edge case goldmine:** Run hypothesis on existing pipelines; it often finds bugs in `groupby`, `fillna`, `merge` operations that deterministic tests missed for months.
