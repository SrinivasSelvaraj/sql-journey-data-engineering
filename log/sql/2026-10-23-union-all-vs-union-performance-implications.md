---
date: 2026-10-23
phase: sql
topic: Union all vs union: performance implications
---

# Union all vs union: performance implications

*SQL for analytics and engineering*

## Concept

**UNION** removes duplicate rows from the combined result set by applying an implicit `DISTINCT` operation, while **UNION ALL** returns all rows including duplicates. The performance difference is substantial: UNION requires a sort or hash aggregation step to identify and eliminate duplicates, adding CPU and memory overhead. UNION ALL simply concatenates result sets and is typically 2–10× faster depending on data volume and cardinality.

The choice matters most when combining large datasets or running frequently. If your source queries are guaranteed to produce non-overlapping rows (e.g., combining results from different date ranges or job categories), UNION ALL is both correct and faster. Use UNION only when you genuinely need deduplication—otherwise you're paying for work the query engine doesn't need to do.

Without understanding this distinction, you may write correct but severely inefficient queries, especially in analytics pipelines where the same union runs thousands of times. In interview settings, explaining your choice signals awareness of query execution plans and cost.

## Practice

**Problem:** Combine remote and non-remote senior analyst job postings from the last 90 days, avoiding duplicate job IDs. Write the most performant query.

```sql
-- Inefficient: UNION forces unnecessary deduplication
SELECT job_id, job_title_short, salary_year_avg, job_location
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_title_short LIKE '%Senior Analyst%'
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
UNION
SELECT job_id, job_title_short, salary_year_avg, job_location
FROM job_postings_fact
WHERE job_work_from_home = FALSE
  AND job_title_short LIKE '%Senior Analyst%'
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days';

-- Performant: UNION ALL (source queries partition by disjoint condition)
SELECT job_id, job_title_short, salary_year_avg, job_location
FROM job_postings_fact
WHERE job_work_from_home = TRUE
  AND job_title_short LIKE '%Senior Analyst%'
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days'
UNION ALL
SELECT job_id, job_title_short, salary_year_avg, job_location
FROM job_postings_fact
WHERE job_work_from_home = FALSE
  AND job_title_short LIKE '%Senior Analyst%'
  AND job_posted_date >= CURRENT_DATE - INTERVAL '90 days';
```

## Notes

- **Deduplication is expensive**: UNION executes a sort or hash aggregate; check execution plans with `EXPLAIN` to see the cost node. On 100k+ rows, this is measurable.
- **Disjoint partitions are your friend**: If you know rows can't duplicate across branches (e.g., different `job_work_from_home` values), UNION ALL is both correct and faster.
- **Compound keys matter**: Deduplication checks *all* columns; if you only care about uniqueness on `job_id`, use `DISTINCT ON (job_id)` instead to avoid sorting on irrelevant columns.
- **Adjacent topics**: UNION performance connects to `DISTINCT` cost, set operations (`INTERSECT`, `EXCEPT`), and understanding your database's sort algorithms (merge sort vs. quicksort).
- **Common mistake**: Assuming UNION and UNION ALL are interchangeable. They're semantically different; choosing UNION for safety without reasoning about duplicates wastes resources.
