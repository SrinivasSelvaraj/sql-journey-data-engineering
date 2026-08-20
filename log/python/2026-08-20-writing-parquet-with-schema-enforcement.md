---
date: 2026-08-20
phase: python
topic: Writing Parquet with schema enforcement
---

# Writing Parquet with schema enforcement

*Python for data engineering*

## Concept

Schema enforcement in Parquet writing ensures that data matches a predefined structure before serialization, preventing silent data corruption and downstream pipeline failures. Without it, type mismatches (strings written as integers, missing columns, extra fields) slip into your files undetected, only to cause cryptic errors when readers encounter them weeks later. This is especially critical in production pipelines where bad input data is inevitable—schema enforcement acts as a guardrail that fails fast and loud rather than letting garbage data propagate.

Parquet's columnar format is strict by nature, but Python libraries like PyArrow let you either enforce schemas explicitly or infer them loosely from data. Explicit schema enforcement means declaring column names, types, and nullability upfront, then validating every write against that contract. This catches type coercion bugs (a date stored as a string), missing required fields, and unexpected columns before they become your data quality problem.

## Practice

**Problem:** You receive daily job posting data as JSON with inconsistent types and missing dates. The `job_posted_date` sometimes arrives as a string "2024-01-15", sometimes as a Unix timestamp, sometimes missing entirely. Writing without schema enforcement lets these silently convert or truncate, corrupting your fact table. How do you enforce the DATE type and reject malformed records?

```python
import pyarrow as pa
import pyarrow.parquet as pq
from datetime import date
import pandas as pd

# Define strict schema
schema = pa.schema([
    pa.field("job_id", pa.int64(), nullable=False),
    pa.field("job_title_short", pa.string(), nullable=False),
    pa.field("salary_year_avg", pa.int64(), nullable=True),
    pa.field("job_work_from_home", pa.bool_(), nullable=False),
    pa.field("job_posted_date", pa.date32(), nullable=False),
    pa.field("job_location", pa.string(), nullable=True),
])

# Convert and validate before write
df = pd.read_json("job_postings.json")
df["job_posted_date"] = pd.to_datetime(df["job_posted_date"]).dt.date

try:
    table = pa.Table.from_pandas(df, schema=schema)
    pq.write_table(table, "job_postings_fact.parquet")
except pa.ArrowInvalid as e:
    print(f"Schema validation failed: {e}")
    # Log bad records, alert, retry with cleaning logic
```

## Notes

- **Type coercion surprises:** PyArrow silently casts some types (int → float) but rejects others (string → int). Always test your actual input data against your schema in staging first.

- **Nullability is a contract:** Setting `nullable=False` makes the schema reject NULL values. Be deliberate about which columns truly cannot be missing; over-constraining causes failed writes when upstream data is incomplete.

- **Schema evolution:** As pipelines mature, you'll need to add columns or change types. Document your schema version alongside the Parquet file (e.g., in metadata) or use schema registries (Confluent Schema Registry) for multi-team coordination.

- **Testing opportunity:** Unit tests should include: valid data, NULL in nullable columns, missing nullable columns, and intentionally bad data (wrong types, out-of-range dates) to verify rejection logic works.

- **Adjacent skills:** Connects to partition pruning (schema determines what can be partitioned), Parquet metadata inspection (`pq.read_schema()`), and data validation frameworks like Great Expectations.
