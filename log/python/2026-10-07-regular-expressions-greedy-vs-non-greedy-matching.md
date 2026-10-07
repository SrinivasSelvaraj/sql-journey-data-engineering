---
date: 2026-10-07
phase: python
topic: Regular expressions: greedy vs non-greedy matching
---

# Regular expressions: greedy vs non-greedy matching

*Python for data engineering*

## Concept

Greedy matching (`.*`, `.+`) consumes as much input as possible before backtracking; non-greedy matching (`.*?`, `.+?`) stops as soon as the pattern matches. In data pipelines, greedy matching often over-captures when you're extracting structured fields from messy text—for example, pulling a salary range from a job description that contains multiple price mentions. Non-greedy is essential when parsing delimited or semi-structured data where you want to stop at the *first* occurrence of a delimiter, not the last.

The difference matters most when your regex straddles multiple tokens or when input contains unexpected repetition. Without choosing correctly, you'll silently extract wrong values: a greedy `".*"` around a field boundary might grab across multiple records, while non-greedy `".*?"` stops at the first natural boundary. This is a silent failure mode—your pipeline runs, produces data, but the data is corrupted.

In typed, testable code, this manifests as unit test failures on edge cases. Build regex tests *before* deploying extraction logic to production, and always verify behavior on inputs with repeated delimiters or multiple matches.

## Practice

**Problem:** Extract the minimum salary from a job posting text that may contain multiple salary mentions. The text format is `"Salary range: $50k–$80k, competitive with market rates of $60k–$90k."` We need only the first mention's minimum value.

```python
import re
from typing import Optional

def extract_min_salary_from_text(text: str) -> Optional[int]:
    """Extract the first salary minimum mentioned in job posting text."""
    # Non-greedy: .*? stops at the first $ mention
    match = re.search(r'Salary range: \$(\d+)k–\$\d+k', text)
    if match:
        return int(match.group(1)) * 1000
    return None

# Greedy equivalent (incorrect for multi-mention text):
def extract_min_salary_greedy(text: str) -> Optional[int]:
    # .* consumes to the *last* digit group, may skip intermediate mentions
    match = re.search(r'.*\$(\d+)k', text)
    if match:
        return int(match.group(1)) * 1000
    return None

# Test cases
test_text = "Salary range: $50k–$80k, competitive with market rates of $60k–$90k."
assert extract_min_salary_from_text(test_text) == 50000
assert extract_min_salary_greedy(test_text) == 90000  # Wrong!
```

## Notes

- **Greedy as default trap:** Python regex uses greedy quantifiers by default; you must explicitly add `?` to switch. Code review should flag `.* ` or `.+` in extraction logic—require justification.
- **Anchors + non-greedy together:** `^text.*?end$` is safer than just `.*?end` because anchors limit the scope; without them, non-greedy can still match across unexpected boundaries.
- **Test on delimiters:** Always include test cases where the pattern appears multiple times in one string. Greedy/non-greedy behavior only differs here; single-match tests hide bugs.
- **Related: atomic groups and possessive quantifiers:** In complex patterns, `(?>...)` and `*+` prevent backtracking entirely—useful when greedy/non-greedy alone don't solve performance or correctness issues.
- **Revisit for SQL/Spark:** REGEXP_SUBSTR and similar functions in SQL have their own greedy semantics; validate behavior differs from Python re module before porting extraction logic.
