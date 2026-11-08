---
date: 2026-11-08
phase: python
topic: Generators and yield: memory-efficient iteration and lazy evaluation
---

# Generators and yield: memory-efficient iteration and lazy evaluation

*Python for data engineering*

## Concept

Generators are functions that yield values one at a time rather than building and returning an entire collection. They use the `yield` keyword to pause execution, saving state, and resume on the next iteration. In data engineering, generators are critical for processing large datasets—streaming a 1 GB CSV file through a generator uses constant memory, while loading it into a list exhausts RAM. Lazy evaluation means computation happens only when demanded (when you call `next()` or iterate), not upfront.

Without generators, you either load entire datasets into memory (dangerous at scale) or write complex stateful classes to manage iteration. A generator elegantly handles both the iteration protocol and memory efficiency. They pair naturally with pipelines: read → transform → filter → aggregate, where each stage yields results to the next without buffering intermediate collections.

## Practice

**Problem:** You need to process 50 million job postings from a CSV, filter for remote Python roles with salary > $120k, and yield only the job IDs and titles without loading the entire file into memory.

```python
def filter_remote_high_pay_jobs(csv_file_path: str) -> Generator[tuple[int, str], None, None]:
    """Lazily read and filter job postings."""
    with open(csv_file_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                job_id = int(row['job_id'])
                title = row['job_title_short']
                salary = int(row['salary_year_avg']) if row['salary_year_avg'] else 0
                is_remote = row['job_work_from_home'].lower() == 'true'
                
                if is_remote and salary > 120000 and 'python' in title.lower():
                    yield (job_id, title)
            except (ValueError, KeyError) as e:
                logging.warning(f"Skipping row {row.get('job_id', '?')}: {e}")
                continue

# Usage: iterate without loading 50M rows
for job_id, title in filter_remote_high_pay_jobs('jobs.csv'):
    process_job(job_id, title)
```

## Notes

- **Generator vs list:** `(x for x in range(1000000))` is lazy; `[x for x in range(1000000)]` allocates 8+ MB immediately. Know which you're building.
- **Consuming a generator exhausts it:** Once you iterate through a generator, it's done. If you need to iterate twice, either consume into a list or recreate the generator.
- **Type hints matter:** Use `Generator[YieldType, SendType, ReturnType]` from `typing` (or `collections.abc` in 3.9+). The three types clarify contract.
- **Error handling in generators:** Wrap loops with try/except and log/skip bad rows rather than crashing the whole pipeline. Generators can silently skip malformed input if not careful.
- **Adjacent topics:** Connects to itertools (`chain`, `islice`, `groupby`), async generators (`async def` + `yield`), and context managers (`with` statement for safe resource cleanup in pipelines).
