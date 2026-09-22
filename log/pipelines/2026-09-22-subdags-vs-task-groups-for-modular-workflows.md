---
date: 2026-09-22
phase: pipelines
topic: SubDAGs vs task groups for modular workflows
---

# SubDAGs vs task groups for modular workflows

*Pipelines and orchestration*

## Concept

SubDAGs and task groups are both mechanisms for organizing complex Airflow workflows into logical, reusable units—but they differ fundamentally in scope and reusability. SubDAGs are separate DAG objects that run as a single task within a parent DAG; task groups are purely a UI/organizational construct that group tasks within the same DAG context. SubDAGs add scheduling overhead and create a parent-child DAG relationship that complicates error handling and retry logic. Task groups have no runtime overhead and inherit the parent DAG's scheduling, making them the modern preference for modular workflows in Airflow 2.0+.

The distinction matters most when you need independent reusability (SubDAGs shine here, though with cost) versus clean logical organization without scheduling complexity (task groups). Without proper modularization, large pipelines become difficult to test, monitor, and modify. A 200-task job posting ETL becomes a hairball of dependencies where a single sensor failure cascades unpredictably. SubDAGs and task groups let you encapsulate patterns—e.g., "validate then load"—so teams can reason about failure domains and retry behavior separately.

## Practice

**Problem:** The job_postings_fact table needs a modular pipeline: extract job postings from an API, validate salary and location fields, deduplicate by job_id, then load to warehouse. Without modularization, debugging which step failed becomes tedious. Build this using task groups.

```python
from airflow.decorators import dag, task
from airflow.utils.task_group import TaskGroup
from datetime import datetime
import pendulum

@dag(dag_id="job_postings_etl", start_date=pendulum.datetime(2024, 1, 1), catchup=False)
def job_postings_pipeline():
    
    @task
    def check_api_availability():
        # Sensor-like task
        return True
    
    with TaskGroup("extract") as extract_tg:
        @task
        def fetch_job_postings():
            # Call API, return raw data
            return [{"job_id": 1, "title": "Data Engineer", "salary": 120000}]
        
        @task
        def store_raw(data):
            # Land in staging table
            return len(data)
        
        fetch_job_postings() >> store_raw(fetch_job_postings())
    
    with TaskGroup("validate") as validate_tg:
        @task
        def check_salary_range():
            # Ensure salary_year_avg is between 30k and 500k
            return True
        
        @task
        def check_location_not_null():
            # Ensure job_location is populated
            return True
        
        check_salary_range() >> check_location_not_null()
    
    with TaskGroup("load") as load_tg:
        @task
        def deduplicate_by_job_id():
            # Remove duplicates, keep latest by job_posted_date
            return 1000
        
        @task
        def insert_job_postings_fact(row_count):
            # INSERT INTO job_postings_fact
            return f"Loaded {row_count} rows"
        
        deduplicate_by_job_id() >> insert_job_postings_fact(deduplicate_by_job_id())
    
    check_api_availability() >> extract_tg >> validate_tg >> load_tg

job_postings_etl()
```

## Notes

- **Task groups are Airflow 2.0+ best practice:** SubDAGs are deprecated conceptually; they add scheduling overhead and complicate retry logic because a SubDAG failure requires re-running the entire parent DAG. Task groups have zero runtime cost and inherit parent scheduling elegantly.

- **Mistake: Over-nesting task groups.** Deep hierarchies (extract > raw_validation > schema_validation > business_validation) harm readability. Aim for 2–3 levels maximum; flatten when possible.

- **Adjacent: Backfill and idempotency.** Modular pipelines enable safe backfilling because you can isolate and re-run specific stages. Without clear task boundaries, you risk duplicate inserts or missed partitions. Each task group should be independently idempotent (same inputs → same state, no side effects from reruns).

- **Monitoring and alerting connect here:** Task groups let you set SLAs and alert on specific stages (e.g., alert if validate takes >10min). Monolithic DAGs hide where time is spent; modular ones make bottlenecks visible.

- **Revisit: Dynamic task mapping + task groups.** When you need to parallelize the same subgraph across many job posting batches, combine task groups with `expand()` for powerful, scalable patterns that would be nightmare-level complex without modularization.
