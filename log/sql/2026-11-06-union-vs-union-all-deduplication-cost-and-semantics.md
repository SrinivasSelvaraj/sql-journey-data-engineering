---
date: 2026-11-06
phase: sql
topic: Union vs union all: deduplication cost and semantics
---

# Union vs union all: deduplication cost and semantics

*SQL for analytics and engineering*

## Concept

`UNION` removes duplicates by performing an implicit `DISTINCT` on the combined result set, while `UNION ALL` returns all rows from both queries without deduplication. The cost difference is significant: `UNION` requires a sort or hash operation to identify and eliminate duplicates, adding CPU and memory overhead. `UNION ALL` is a simple row concatenation and should be your default unless you explicitly need deduplication semantics.

The choice matters most when combining large datasets. A `UNION` on two 10M-row tables can add 5–10× query time compared to `UNION ALL` if duplicates are rare. Semantically, use `UNION` only when your domain logic requires it—for instance, combining customer lists from two separate systems where you want a single view per customer. Using `UNION` carelessly masks data quality issues and can hide unintended duplicates upstream.

Without understanding this distinction, you risk writing slow queries that appear correct but waste resources, or returning incomplete results if you use `UNION ALL` when deduplication was needed. In interviews, this is a common way to demonstrate understanding of execution plans and intentional query design.

## Practice

**Problem:** You're building a report showing unique job locations that offer either remote work *or* salaries above $150k (or both). You want one row per location, and you're combining two separate queries that might overlap.

```sql
SELECT DISTINCT job_location
FROM job_postings_fact
WHERE job_work_from_home = true

UNION

SELECT DISTINCT job_location
FROM job_postings_fact
WHERE salary_year_avg > 150000;
```

This uses `UNION` because the business requirement is "unique locations meeting either criterion." The `DISTINCT` in each subquery is redundant (the `UNION` handles deduplication), but it's defensive. If you used `UNION ALL`, you'd see duplicate locations for places that satisfy both conditions. If you knew there were no overlapping locations by design, you'd switch to `UNION ALL` for performance.

## Notes

- **Common mistake:** Using `UNION` by habit without checking if duplicates are even possible. Always ask: "Will these two result sets actually overlap?" If no, `UNION ALL` is faster and correct.
- **Execution plan signal:** In most databases, `UNION` adds a sort or hash aggregate node. Look for this in `EXPLAIN` output; it's a red flag for performance tuning.
- **Data quality insight:** Unexpected duplicates from `UNION ALL` often reveal upstream issues (late-arriving facts, duplicate source records). Don't suppress them with `UNION` without investigating.
- **Composite keys:** Deduplication considers all columns. `UNION` on two tables with different column counts will fail; `UNION ALL` is more forgiving (though both require matching column types and counts).
- **Related topics:** Revisit `GROUP BY` (another deduplication mechanism), `INTERSECT` / `EXCEPT` (set operations), and window functions as alternatives for avoiding redundant rows without the cost of full deduplication.
