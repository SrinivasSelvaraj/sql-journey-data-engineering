---
date: 2026-10-25
phase: python
topic: Composition over inheritance for pipeline stages
---

# Composition over inheritance for pipeline stages

*Python for data engineering*

## Concept

Composition over inheritance means building pipeline stages by *combining* small, single-responsibility objects rather than creating deep class hierarchies. In data pipelines, this means each stage (extract, validate, transform, load) is a standalone class with a common interface—not a base class with many overridden methods. When you inherit heavily, you inherit baggage: a parent's validation logic breaks your child stage, a shared error handler doesn't fit all cases, or adding one feature requires touching five subclasses.

Inheritance gets painful fast in pipelines because stages have genuinely different concerns. A CSV reader shouldn't share code paths with a database extractor just because both are "extractors." A schema validator shouldn't be tangled with a deduplication transformer. Composition lets you build `ValidateThenTransform(Validator(), Transformer())` and test each piece independently. This matters most when your pipeline must handle bad input—missing files, null columns, type mismatches—without cascading failures through a brittle class tree.

## Practice

**Problem:** Build a reusable pipeline that extracts job postings, validates required fields (job_id, job_title_short, salary_year_avg cannot be null), transforms salary to thousands, and loads into a fact table. The validation rules are strict; the transform is simple; loading may fail and should be retried. How do you structure this so each stage can be tested and swapped independently?

```python
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import List, Optional

@dataclass
class PipelineContext:
    data: List[dict]
    errors: List[str] = None
    
    def __post_init__(self):
        if self.errors is None:
            self.errors = []

class Stage(ABC):
    @abstractmethod
    def execute(self, ctx: PipelineContext) -> PipelineContext:
        pass

class ExtractJobPostingsCSV(Stage):
    def __init__(self, filepath: str):
        self.filepath = filepath
    
    def execute(self, ctx: PipelineContext) -> PipelineContext:
        # Simulate CSV read
        ctx.data = [
            {"job_id": 1, "job_title_short": "Data Engineer", "salary_year_avg": 120000},
            {"job_id": 2, "job_title_short": None, "salary_year_avg": 95000},
        ]
        return ctx

class ValidateRequiredFields(Stage):
    def __init__(self, required_fields: List[str]):
        self.required_fields = required_fields
    
    def execute(self, ctx: PipelineContext) -> PipelineContext:
        validated = []
        for row in ctx.data:
            if all(row.get(field) is not None for field in self.required_fields):
                validated.append(row)
            else:
                ctx.errors.append(f"Row missing required fields: {row}")
        ctx.data = validated
        return ctx

class TransformSalaryToThousands(Stage):
    def execute(self, ctx: PipelineContext) -> PipelineContext:
        for row in ctx.data:
            row["salary_year_avg"] = row["salary_year_avg"] / 1000
        return ctx

class LoadToFactTable(Stage):
    def __init__(self, table_name: str, max_retries: int = 3):
        self.table_name = table_name
        self.max_retries = max_retries
    
    def execute(self, ctx: PipelineContext) -> PipelineContext:
        # Simulate insert with retry logic
        for attempt in range(self.max_retries):
            try:
                # INSERT INTO job_postings_fact ...
                print(f"Loaded {len(ctx.data)} rows to {self.table_name}")
                return ctx
            except Exception as e:
                if attempt == self.max_retries - 1:
                    ctx.errors.append(f"Load failed after {self.max_retries} retries: {e}")
        return ctx

class Pipeline:
    def __init__(self, stages: List[Stage]):
        self.stages = stages
    
    def run(self, ctx: PipelineContext) -> PipelineContext:
        for stage in self.stages:
            ctx = stage.execute(ctx)
        return ctx

# Usage
pipeline = Pipeline([
    ExtractJobPostingsCSV("jobs.csv"),
    ValidateRequiredFields(["job_id", "job_title_short", "salary_year_avg"]),
    TransformSalaryToThousands(),
    LoadToFactTable("job_postings_fact"),
])

result = pipeline.run(PipelineContext(data=[]))
print(f"Errors: {result.errors}")
print(f"Loaded data: {result.data}")
```

## Notes

- **Inheritance trap:** Don't create `BaseStage` with shared logging/error handling—each stage composes a `Logger` and `Error
