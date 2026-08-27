---
date: 2026-08-27
phase: python
topic: Generator expressions vs list comprehensions for memory efficiency
---

# Generator expressions vs list comprehensions for memory efficiency

*Python for data engineering*

## Concept

Generator expressions and list comprehensions both iterate over sequences in Python, but generators yield one value at a time without storing the entire result in memory, while list comprehensions build the full list upfront. For data pipelines processing millions of rows, this distinction is critical: a list comprehension on 10M records consumes gigabytes of RAM, while a generator streams through the same data in constant memory. Generators are lazy—they compute values only when requested, making them ideal for ETL stages where you transform data row-by-row before loading. However, generators can only be iterated once and don't support indexing or len(), which breaks code expecting list-like behavior.

The choice matters most at pipeline boundaries: use generators when chaining transformations (read → filter → map → write) or when data size is unknown. Use list comprehensions when you need random access, must pass data to multiple consumers, or are working with small reference datasets (<100K items). Without this discipline, a pipeline that works on sample data will crash in production with MemoryError when fed realistic volumes.

## Practice

**Problem:** Extract high-paying remote jobs from the fact table, apply a salary floor of $120k USD, and pass the results to both a CSV writer and an analytics aggregator. The dataset has 5M rows.

**Solution:**

```python
# ❌ Memory inefficient—builds full list in RAM
high_paying_remote = [
    row for row in fetch_job_postings_fact()
    if row['salary_year_avg'] > 120000 and row['job_work_from_home']
]

# ✅ Generator expression—streams one row at a time
high_paying_remote = (
    row for row in fetch_job_postings_fact()
    if row['salary_year_avg'] > 120000 and row['job_work_from_home']
)

# ✅ Better: convert to list only where needed (CSV write)
csv_writer.writerows(high_paying_remote)

# ❌ This fails—generator already exhausted above
analytics.aggregate(high_paying_remote)

# ✅ Correct: rebuild or use itertools.tee() for multiple consumers
iter1, iter2 = itertools.tee(high_paying_remote, 2)
csv_writer.writerows(iter1)
analytics.aggregate(iter2)
```

## Notes

- **Generator exhaustion trap:** Once you iterate a generator with `for` or `list()`, it's empty. Don't pass the same generator to multiple functions; use `itertools.tee()` to split the stream.
- **Type-checking gotcha:** Type hints like `list[dict]` and `Generator[dict, None, None]` are different. Strict type checking will reject a generator where a list is expected; use `Iterable[dict]` in function signatures to accept both.
- **Debugging challenge:** Generators hide errors until iteration. A broken filter condition won't surface until you consume rows. Add logging *inside* the generator expression or use `map(log_and_yield, generator)` to catch issues early.
- **Adjacent pattern—itertools:** `chain()`, `tee()`, `islice()`, and `cycle()` are your allies for composing lazy transformations without pandas. Learn these to build efficient pipeline stages.
- **Revisit:** Consider generators again when you encounter windowing operations, stateful transformations (e.g., running totals), or multi-pass algorithms where you need to store intermediate results strategically rather than greedily.
