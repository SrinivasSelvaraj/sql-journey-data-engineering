---
date: 2026-08-28
phase: python
topic: Debugging with pdb: breakpoints, post-mortem and remote debug
---

# Debugging with pdb: breakpoints, post-mortem and remote debug

*Python for data engineering*

## Concept

Debugging with pdb is Python's built-in debugger that lets you pause execution, inspect state, and step through code line-by-line. In data pipelines, this is critical because failures often occur deep in transformations—a corrupt row, a silent type mismatch, or unexpected None values. Without debugging tools, you're reduced to print statements and guessing; with pdb, you can set breakpoints before a crash happens, drop into a post-mortem session *after* an exception, or attach to a running remote process to see exactly what the data looks like at failure time.

In data engineering, a single malformed record can propagate through joins and aggregations, making the root cause invisible by the time you see it downstream. pdb breakpoints let you validate assumptions at each pipeline stage. Post-mortem debugging (`pdb.post_mortem()` or `python -m pdb script.py`) catches unhandled exceptions and freezes the stack in place so you can inspect local variables. Remote debugging matters when your pipeline runs on a cluster or container—you can forward ports and attach a debugger to the live process without halting it.

## Practice

**Problem:** Your ETL loads job postings into a fact table. Some records have `job_posted_date = NULL`, and you suspect it's corrupting downstream salary aggregations. You need to catch the exact row and understand why the date parsing failed.

```python
import pdb
from datetime import datetime

def load_job_postings(raw_data: list[dict]) -> list[dict]:
    """Transform and validate job posting records."""
    cleaned = []
    for idx, row in enumerate(raw_data):
        try:
            # Breakpoint before parsing—inspect raw row
            if idx == 5:  # Set for a specific row that might fail
                pdb.set_trace()
            
            parsed_date = datetime.strptime(row['posted_date'], '%Y-%m-%d').date()
            
            cleaned.append({
                'job_id': row['job_id'],
                'job_title_short': row['title'],
                'salary_year_avg': float(row['salary']) if row['salary'] else None,
                'job_work_from_home': row.get('remote', False),
                'job_posted_date': parsed_date,
                'job_location': row['location']
            })
        except ValueError as e:
            # Post-mortem: drop into debugger on exception
            print(f"Failed on row {idx}: {row}")
            pdb.post_mortem()
    
    return cleaned

# Alternative: wrap main entry for automatic post-mortem
if __name__ == '__main__':
    try:
        result = load_job_postings(raw_postings)
    except Exception:
        import sys
        pdb.post_mortem(sys.exc_info()[2])
```

## Notes

- **Breakpoint placement:** Use `pdb.set_trace()` *before* the suspicious line, not after. Step through with `n` (next), `s` (step into function), `c` (continue), and `p variable_name` (print value). Avoid placing breakpoints inside tight loops unless filtered by condition.

- **Post-mortem vs. breakpoints:** Breakpoints are preventative (you pause before known risk); post-mortem is reactive (you inspect the crash site after it happens). In production, always wrap entry points with try/except and post-mortem for unhandled exceptions so you can diagnose without rerunning.

- **Remote debugging:** Use `pdbpp` or `debugpy` for containers. Forward ports: `docker run -p 5678:5678 image` and connect from your IDE. For Spark, attach the debugger to the driver process only, not executors—debugging 100 executors at once is chaos.

- **Related:** Type hints + mypy catch many issues before runtime; pdb complements them. Unit tests should break at the same pdb line you'd hit in prod—if not, your test coverage is missing the failure mode.

- **Revisit:** Learn `ipdb` for colored output and better tab completion; `breakpoint()` (Python 3.7+) auto-selects your debugger; configure your IDE's debugger integration so you don't live in the terminal.
