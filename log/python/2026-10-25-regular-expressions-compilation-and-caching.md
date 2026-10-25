---
date: 2026-10-25
phase: python
topic: Regular expressions compilation and caching
---

# Regular expressions compilation and caching

*Python for data engineering*

## Concept

Regular expressions are powerful for extracting and validating patterns in text data, but compiling the same pattern repeatedly during pipeline execution wastes CPU cycles and memory. Python's `re` module caches compiled patterns automatically (up to 512 by default), but relying on implicit caching is fragile—once you exceed the cache size or run distributed jobs, you lose that benefit. Explicitly compiling and caching regex patterns gives you control, makes performance predictable, and is essential when processing millions of rows where a single pattern match per row can compound into seconds of wasted work.

Without caching, a pipeline that extracts job titles from noisy text or validates email formats will recompile the same regex on every row. With caching, you compile once at module load time and reuse the compiled pattern object. This is especially critical in data pipelines because the pattern is static—it doesn't change between rows—so caching is a guaranteed win with no downside.

## Practice

**Problem:** Extract salary ranges from job postings where the salary field is messy text like "80K–120K", "$80,000 to $120,000", or "80k-120k". You need to validate the format before inserting into `job_postings_fact`, and parse min/max salary values reliably without recompiling the regex for each row.

```python
import re
from typing import Optional, Tuple

# Compile once at module load
SALARY_PATTERN = re.compile(
    r'\$?(\d{1,3}(?:,\d{3})*|\d+)[kK]?[\s\-–to]*\$?(\d{1,3}(?:,\d{3})*|\d+)[kK]?',
    re.IGNORECASE
)

def extract_salary_range(text: str) -> Optional[Tuple[int, int]]:
    """Extract min and max salary from messy text."""
    if not text or not isinstance(text, str):
        return None
    
    match = SALARY_PATTERN.search(text.strip())
    if not match:
        return None
    
    try:
        min_sal = int(match.group(1).replace(',', ''))
        max_sal = int(match.group(2).replace(',', ''))
        
        # Normalize if in thousands
        if min_sal < 1000 or max_sal < 1000:
            min_sal *= 1000
            max_sal *= 1000
        
        return (min_sal, max_sal) if min_sal <= max_sal else None
    except (ValueError, AttributeError):
        return None

# Usage in pipeline
for row in job_postings:
    salary_range = extract_salary_range(row['salary_text'])
    avg_salary = (salary_range[0] + salary_range[1]) // 2 if salary_range else None
```

## Notes

- **Cache size matters in distributed jobs:** each worker process has its own cache; explicit module-level compilation ensures consistency across Spark executors or Dask workers.
- **Use `re.compile()` at module scope, not inside functions:** lazy evaluation in functions defeats the purpose and adds latency on first call.
- **Raw strings (`r''`) are mandatory:** without them, backslash escapes get interpreted by Python before regex sees them, causing hard-to-debug failures.
- **Regex validation belongs in data ingestion, not transformation:** catch bad patterns early with `PATTERN.match()` or `.search()`, then fail fast; this keeps bad data out of your fact table.
- **Adjacent topics:** precompile regex in unit tests to catch pattern errors before production; combine with Pydantic validators for type-safe extraction; consider `regex` library as drop-in replacement for complex patterns (lookahead, conditionals).
