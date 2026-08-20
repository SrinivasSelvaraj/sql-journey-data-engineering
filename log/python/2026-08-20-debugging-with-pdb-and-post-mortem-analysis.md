---
date: 2026-08-20
phase: python
topic: Debugging with pdb and post-mortem analysis
---

# Debugging with pdb and post-mortem analysis

*Python for data engineering*

## Concept

Debugging with pdb (Python Debugger) lets you pause execution, inspect state, and step through code line-by-line. Post-mortem analysis means examining a crashed program's final state without re-running it—pdb.pm() drops you into the traceback immediately after failure. This is essential in data pipelines because production failures are often irreproducible: bad input at row 50,000, race conditions in async jobs, or silent data type coercions that corrupt downstream aggregations.

Without interactive debugging, you're left with print statements and logs, which force you to guess what variables contained at crash time. With pdb, you inspect the exact call stack, local/global scope, and can execute arbitrary code to test hypotheses. For pipelines, this prevents hours of reprocessing large datasets to reproduce a bug that happened once in production.

## Practice

**Problem:** A data quality check passes locally but fails in production. Your pipeline loads job postings, filters for remote work (job_work_from_home = true), and calculates median salary. In production, median salary returns NULL for remote jobs even though salary_year_avg has values. You suspect type coercion or NULL handling.

```python
import pdb
import pandas as pd
from sqlalchemy import create_engine

engine = create_engine('postgresql://...')
df = pd.read_sql('SELECT * FROM job_postings_fact WHERE job_work_from_home = true', engine)

# Trigger post-mortem on unexpected NULL
if df['salary_year_avg'].median() is None and len(df) > 0:
    pdb.post_mortem()  # Drops into debugger at this line

# Or wrap transformation logic for immediate inspection on error
try:
    median_sal = df['salary_year_avg'].astype(float).median()
except Exception:
    import pdb, traceback
    traceback.print_exc()
    pdb.pm()  # Examine state when exception occurred

# Within pdb, inspect:
# (Pdb) df['salary_year_avg'].dtype
# (Pdb) df['salary_year_avg'].isna().sum()
# (Pdb) df['salary_year_avg'].head()
```

## Notes

- **Common mistake:** Relying on print-debugging in loops; use conditional breakpoints (`pdb.set_trace() if row_id == 999999 else None`) to halt only on problem rows.
- **Type coercion trap:** In pipelines, string columns silently stay strings; use `df.dtypes` and `df.astype()` explicitly—pdb reveals when a column is object instead of float64.
- **Post-mortem requires active sessions:** pdb.pm() only works in interactive environments; for batch jobs, catch exceptions and log full tracebacks, then reproduce locally with that data subset.
- **Adjacent: Logging and structured debugging** — pdb is tactical; use logging.basicConfig(level=DEBUG) for strategic insight into long-running jobs. Combine pdb for one-off failures, structured logs for patterns.
- **Revisit: Unit testing with pytest.raises()** — catch and assert on exceptions before they reach production, reducing post-mortem frequency.
