---
date: 2026-09-03
phase: pipelines
topic: Testing DAGs: structure validation and dry-run execution
---

# Testing DAGs: structure validation and dry-run execution

*Pipelines and orchestration*

## Concept

DAG testing validates that your orchestrated workflows are correctly structured *before* they run in production, catching configuration errors, missing dependencies, and logical flaws early. Structure validation checks that tasks exist, dependencies form a valid graph (no cycles), parameters are defined, and connections between systems are declared. Dry-run execution simulates task execution without writing data, verifying that queries parse, file paths resolve, and API credentials work—all in a safe sandbox environment.

Without DAG testing, you discover problems at 2am when a critical job fails mid-run because a downstream task references a non-existent upstream output, or a SQL query syntax error wasn't caught until production load. Validation catches these before the DAG ever touches real data. Structure testing is especially critical in complex multi-team pipelines where one engineer's task misconfiguration cascades into ten failed dependents.

## Practice

**Problem:** Your DAG loads job postings data into `job_postings_fact`. You have a branching workflow: one path transforms salary data (requires `salary_year_avg` to be non-null), another validates remote-work eligibility (requires `job_work_from_home` column). Both paths must complete before a final aggregate task runs. Test that the DAG structure is valid and a dry-run doesn't fail on missing columns or NULL assumptions.

```sql
-- Structure validation: verify input columns exist and required fields are non-null
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  job_location,
  CASE 
    WHEN salary_year_avg IS NULL THEN 'WARN: salary_path will filter this row'
    ELSE 'OK'
  END as salary_path_status,
  CASE 
    WHEN job_work_from_home IS NULL THEN 'WARN: remote_path will filter this row'
    ELSE 'OK'
  END as remote_path_status
FROM job_postings_fact
LIMIT 100;

-- Dry-run: test aggregation logic without materializing
WITH salary_branch AS (
  SELECT job_id, AVG(salary_year_avg) as avg_salary
  FROM job_postings_fact
  WHERE salary_year_avg IS NOT NULL
  GROUP BY job_id
),
remote_branch AS (
  SELECT job_id, COUNT(*) as remote_job_count
  FROM job_postings_fact
  WHERE job_work_from_home = TRUE
  GROUP BY job_id
)
SELECT 
  COALESCE(s.job_id, r.job_id) as job_id,
  s.avg_salary,
  r.remote_job_count
FROM salary_branch s
FULL OUTER JOIN remote_branch r ON s.job_id = r.job_id
LIMIT 10;
```

## Notes

- **Cycle detection:** Always visualize your DAG graph—tools like Airflow's UI or dbt's `dbt dag` command reveal unintended circular dependencies that will deadlock at runtime.
- **Parameter injection mistakes:** Typos in variable references (`{{ var.value.table_name }}` vs `{{ var.value.tablename }}`) silently pass YAML validation but fail during execution; dry-run catches them immediately.
- **Adjacent topics:** Connect DAG testing to data contracts (schema validation), idempotency (safe reruns), and observability (logging which branch executed and why).
- **Test incrementally:** Validate structure first (fast, catches 80% of errors), then dry-run with small sample data (catches logic errors), then run on full volume.
- **Revisit:** After any DAG refactor—moving tasks, changing dependencies, adding parallelism—re-validate; complex orchestration logic degrades quickly without discipline.
