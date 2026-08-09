---
date: 2026-08-09
phase: python
topic: pandas: vectorisation vs iterrows
---

# pandas: vectorisation vs iterrows

*Python for data engineering*

## Concept

Vectorisation in pandas means applying operations to entire columns at once using built-in methods, rather than looping row-by-row with `iterrows()`. When you use `iterrows()`, pandas converts each row to a Series, applies your logic, and reconstructs the DataFrame—this is slow because the loop happens in Python, not optimised C code underneath. Vectorised operations like `.apply()`, `.str` accessors, or numpy operations stay within pandas' optimised layer.

This matters in data pipelines because processing 100K+ rows with `iterrows()` can take minutes when vectorised equivalents complete in milliseconds. Without vectorisation, your pipeline becomes a bottleneck; with it, you unblock downstream tasks. It also affects testability: vectorised code is easier to unit-test because you're testing numpy/pandas functions with predictable behaviour, not custom loops prone to off-by-one errors.

What breaks: memory pressure (iterating holds entire DataFrames in memory longer), timeout violations in scheduled jobs, and subtle bugs when loop state gets corrupted. Bad input—nulls, type mismatches, edge cases—is harder to debug inside a loop than in a single vectorised call where the error points to the exact operation.

## Practice

**Problem:** From `job_postings_fact`, extract the salary range as a new column `salary_band` by categorising `salary_year_avg` into "Entry" (<50k), "Mid" (50k–100k), "Senior" (>100k), or "Unknown" if null. Do this safely for 500K rows without timeout.

```sql
SELECT
  job_id,
  job_title_short,
  salary_year_avg,
  CASE
    WHEN salary_year_avg IS NULL THEN 'Unknown'
    WHEN salary_year_avg < 50000 THEN 'Entry'
    WHEN salary_year_avg <= 100000 THEN 'Mid'
    ELSE 'Senior'
  END AS salary_band,
  job_work_from_home,
  job_posted_date,
  job_location
FROM job_postings_fact
```

*(In pandas: use `pd.cut()` or `np.select()` instead of row loops)*

## Notes

- **Mistake:** Using `iterrows()` then `df.loc[idx, col] = value` causes SettingWithCopyWarning and is O(n²) on assignment—use `.assign()`, `.map()`, or `.apply()` instead.
- **Mistake:** Forgetting to handle nulls before vectorised operations; `pd.cut()` and string methods fail silently or raise on edge cases—always `.fillna()` or use `pd.cut(..., include_lowest=True)`.
- **Adjacent:** Type hints on your transformation functions (e.g., `def categorise_salary(val: float | None) -> str`) make vectorised `.apply()` self-documenting and testable independently.
- **Revisit:** The pandas `eval()` and `query()` methods push logic to C layer too; combine with `.astype()` to ensure input types before operations.
- **Profiling:** Use `%timeit` in notebooks or `timeit` module in scripts to prove vectorisation wins; a 100× speedup is common and justifies refactoring loop-heavy code.
