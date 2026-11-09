---
date: 2026-11-09
phase: python
topic: Debugging: pdb breakpoints and post-mortem inspection
---

# Debugging: pdb breakpoints and post-mortem inspection

*Python for data engineering*

## Concept

Debugging Python data pipelines requires two complementary techniques: **pdb breakpoints** for interactive inspection during development, and **post-mortem inspection** for analyzing failures after they occur. `pdb.set_trace()` or the `breakpoint()` built-in pauses execution, letting you inspect variables, step through code, and test hypotheses in real time—essential when your pipeline silently produces wrong output rather than crashing. Post-mortem debugging uses `pdb.post_mortem()` or exception hooks to drop into the debugger at the exact frame where an exception occurred, preserving the full call stack and variable state. Without these tools, you're reduced to print statements and log files, which waste hours on data pipelines where the bug might hide in a subtle type mismatch, off-by-one error, or data quality issue that only manifests after processing thousands of rows.

In data engineering, breakpoints matter most at transformation boundaries—where raw data enters your pipeline, after aggregations, and before output. Post-mortem inspection is critical for production-like failures that don't reproduce locally, or when a pipeline crashes deep in a nested function after 2 hours of processing. Both techniques become less relevant once you've built robust unit tests and type hints, but they're indispensable during pipeline development and when inheriting buggy code.

## Practice

**Problem:** Your job posting pipeline loads salary data, but discovers that `salary_year_avg` is NULL for 40% of rows. You suspect the parsing logic is discarding valid values. The raw data shows salaries like "$85,000–$120,000" (a range), but your ETL extracts only exact matches to "$X,XXX" format. Debug the extraction logic and fix it.

```python
import pdb
import re
from typing import Optional

def extract_salary(salary_str: Optional[str]) -> Optional[float]:
    """Extract single salary from string; handle ranges by taking midpoint."""
    if not salary_str or salary_str.strip() == "":
        return None
    
    breakpoint()  # Drop into pdb here to inspect incoming data
    
    # Original broken logic: only matches exact "$X,XXX" format
    match = re.search(r'\$(\d{1,3}(?:,\d{3})*)', salary_str)
    if match:
        return float(match.group(1).replace(',', ''))
    return None

# Post-mortem: if an exception occurs in pipeline, inspect it
def load_and_transform(raw_rows):
    try:
        results = []
        for row in raw_rows:
            salary = extract_salary(row['salary_range'])
            results.append(salary)
        return results
    except Exception as e:
        import pdb; pdb.post_mortem()  # Jump to exception site with full stack

# Fixed logic: extract both bounds of range, return average
def extract_salary_fixed(salary_str: Optional[str]) -> Optional[float]:
    """Extract salary or range midpoint."""
    if not salary_str or salary_str.strip() == "":
        return None
    
    # Match one or two dollar amounts (handles "$85,000–$120,000" and "$85,000")
    matches = re.findall(r'\$(\d{1,3}(?:,\d{3})*)', salary_str)
    if not matches:
        return None
    
    values = [float(m.replace(',', '')) for m in matches]
    return sum(values) / len(values)  # Return average if range
```

## Notes

- **Breakpoint placement:** Put `breakpoint()` just *before* the suspicious code, not after. Inspect inputs, then step through logic with `n` (next) and `s` (step into function).
- **Post-mortem vs. try–except:** Use post-mortem for unexpected exceptions; use try–except with logging for expected edge cases. Don't catch and re-raise silently—that destroys the stack.
- **Type hints as scaffolding:** Adding `-> Optional[float]` to `extract_salary()` catches null-safety bugs early; pdb confirms the assumption matches reality.
- **pdb commands to memorize:** `p var` (print), `pp dict` (pretty-print), `l` (list code), `c` (continue), `w` (where/stack), `u`/`d` (up/down frame).
- **Reconnect to testing:** Once you've debugged interactively and found the root cause, *write a unit test that would have caught it*—e.g., `assert extract_salary_fixed("$85,000–$120,000") == 102500.0`.
