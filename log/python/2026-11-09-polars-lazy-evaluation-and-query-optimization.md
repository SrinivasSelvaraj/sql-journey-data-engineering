---
date: 2026-11-09
phase: python
topic: Polars: lazy evaluation and query optimization
---

# Polars: lazy evaluation and query optimization

*Python for data engineering*

## Concept

Lazy evaluation in Polars defers computation until `.collect()` is called, building an execution plan that the query optimizer can analyze and rewrite before running. This is fundamentally different from eager DataFrames where each operation executes immediately. Lazy evaluation matters because it allows Polars to fuse operations (e.g., combining a filter and select into a single pass), eliminate unnecessary columns early, and push predicates down the chain—reducing memory pressure and I/O on large datasets.

Without lazy evaluation, you risk executing redundant work: filtering after a costly join instead of before, materializing intermediate results that get discarded, or reading entire columns you never use. In pipelines processing millions of rows, these inefficiencies compound quickly. Lazy evaluation forces you to think declaratively about *what* you want, not *how* to get it step-by-step, which also makes testing and composition cleaner.

## Practice

**Problem:** You have job postings data and need to find the average salary for remote data engineer roles posted in the last 90 days, but only for postings with a salary value present. You want to avoid loading unnecessary columns and filtering after aggregation.

```python
import polars as pl
from datetime import datetime, timedelta

# Lazy evaluation—nothing runs yet
lazy_result = (
    pl.scan_csv("job_postings_fact.csv")
    .filter(pl.col("job_posted_date") >= (datetime.now() - timedelta(days=90)).date())
    .filter(pl.col("job_work_from_home") == True)
    .filter(pl.col("salary_year_avg").is_not_null())
    .filter(pl.col("job_title_short").str.contains("Data Engineer"))
    .select(["job_id", "salary_year_avg"])
    .group_by().agg(
        pl.col("salary_year_avg").mean().alias("avg_salary"),
        pl.col("job_id").count().alias("job_count")
    )
)

# Execution happens here; optimizer has reordered and fused operations
result = lazy_result.collect()
print(result)
```

The optimizer will push date and remote filters down to the CSV scan, eliminate unused columns early, and combine predicates before aggregation—all without you writing it explicitly.

## Notes

- **Mistake:** Calling `.collect()` too early in development breaks lazy chains and defeats optimization; defer it until you're ready for results.
- **Mistake:** Mixing lazy and eager operations (e.g., calling `.collect()` mid-pipeline to inspect, then chaining more operations) forces premature materialization and kills optimization.
- **Adjacent topic:** Query plans are inspectable with `.explain()` (default) and `.explain(optimized=True)` to see what the optimizer actually does—invaluable for debugging slow queries.
- **Adjacent topic:** Lazy evaluation pairs with typed schemas; always specify or infer types explicitly to help the optimizer make better decisions about memory and casting.
- **Revisit:** Polars' predicate pushdown and projection pushdown are where most gains come from; understanding these concepts makes you better at writing efficient lazy code without trial-and-error.
