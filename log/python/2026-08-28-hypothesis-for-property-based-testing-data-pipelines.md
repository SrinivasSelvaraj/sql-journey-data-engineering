---
date: 2026-08-28
phase: python
topic: Hypothesis for property-based testing data pipelines
---

# Hypothesis for property-based testing data pipelines

*Python for data engineering*

## Concept

Property-based testing uses generative test frameworks (like Hypothesis in Python) to automatically create diverse inputs and verify that your pipeline maintains invariants across them. Rather than writing a single happy-path test, you define properties—logical rules your data should always satisfy—and the framework generates hundreds of edge cases to find violations.

This matters intensely in data pipelines because bad input arrives constantly: nulls, empty strings, future dates, negative numbers, encoding issues. Manual test cases miss the long tail. Without property-based testing, your pipeline might handle the 20 cases you thought of but crash silently on the 21st, corrupting downstream dashboards and reports.

A typical failure: you transform `salary_year_avg` by dividing by 12 for monthly salary, but never test the case where salary is null or zero. Your type hints say `float`, so the code compiles; your unit test passes; but in production a single malformed CSV row fails the entire job. Property-based testing forces you to reason about *ranges* and *constraints*, not just happy paths.

## Practice

**Problem:** Write a pipeline validation function that ensures salary records maintain the invariant: if `salary_year_avg` is not null, it must be positive and within a reasonable range (e.g., $20k–$500k USD). Test it against hundreds of automatically generated payloads.

```python
from hypothesis import given, strategies as st
from typing import Optional

def validate_salary_record(salary_year_avg: Optional[float]) -> bool:
    """Return True if salary passes pipeline invariants."""
    if salary_year_avg is None:
        return True
    return 20_000 <= salary_year_avg <= 500_000

# Property-based test: salary is either null or in valid range
@given(
    salary=st.one_of(
        st.none(),
        st.floats(min_value=0, max_value=1e7, allow_nan=False, allow_infinity=False)
    )
)
def test_salary_invariant(salary):
    result = validate_salary_record(salary)
    if salary is None or (20_000 <= salary <= 500_000):
        assert result is True, f"Valid salary {salary} rejected"
    else:
        assert result is False, f"Invalid salary {salary} accepted"
```

## Notes

- **Don't generate naive ranges:** `st.floats()` without bounds catches NaN and infinity bugs your code might hide. Always exclude pathological values relevant to your domain.
- **Shrinking is your friend:** when Hypothesis finds a failing case, it automatically simplifies it to the minimal example—often revealing the real bug faster than the original massive input.
- **Property-based testing pairs with type hints:** use `Optional[float]`, not just `float`, so your strategy generator and type checker agree on what inputs are possible.
- **Adjacent: schema validation & pydantic models** — consider combining `hypothesis` with Pydantic to generate realistic pipeline records that satisfy both type constraints and business rules simultaneously.
- **Revisit quarterly:** as pipeline requirements shift (new salary caps, new regions), update your property strategies; outdated assumptions are invisible failures.
