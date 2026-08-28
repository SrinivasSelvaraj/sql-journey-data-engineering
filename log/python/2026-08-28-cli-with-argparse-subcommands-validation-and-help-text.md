---
date: 2026-08-28
phase: python
topic: CLI with argparse: subcommands, validation and help text
---

# CLI with argparse: subcommands, validation and help text

*Python for data engineering*

## Concept

Argparse subcommands let you build CLI tools that handle multiple operations—`load`, `transform`, `validate`—each with its own arguments and defaults. This matters in data pipelines because raw input from operators, scripts, or cron jobs will be malformed, incomplete, or wrong. Without validation at the CLI boundary, bad data propagates silently into your pipeline, corrupting intermediate tables or breaking downstream jobs.

Subcommands + argument validation create a contract: only valid input reaches your pipeline logic. Type hints on arguments (choices, type=int, required=True) catch errors early. Help text (–help, descriptions) prevents operators from guessing intent and makes your tool self-documenting. When validation fails, argparse exits with a clear error message before your code runs—this is defensive programming.

## Practice

**Problem:** Write a CLI tool that loads job posting data into a warehouse with subcommands for `load` (file path, table name, mode), `validate` (check date ranges, salary bounds), and `transform` (denormalize or filter). The `load` subcommand must enforce that mode is one of {append, replace, upsert}, dates are ISO format, and salary ranges are sensible (0–500k).

```python
import argparse
from datetime import datetime
from pathlib import Path

def validate_date(date_str: str) -> str:
    try:
        datetime.fromisoformat(date_str)
        return date_str
    except ValueError:
        raise argparse.ArgumentTypeError(f"Invalid date: {date_str}. Use ISO format (YYYY-MM-DD)")

def validate_salary_range(range_str: str) -> tuple[int, int]:
    try:
        min_sal, max_sal = map(int, range_str.split(','))
        if not (0 <= min_sal <= max_sal <= 500000):
            raise ValueError("Salary must be 0–500k and min ≤ max")
        return min_sal, max_sal
    except (ValueError, IndexError) as e:
        raise argparse.ArgumentTypeError(f"Invalid salary range: {range_str}. Use format: min,max (e.g., 50000,150000)")

parser = argparse.ArgumentParser(
    description="Job postings warehouse ETL tool",
    formatter_class=argparse.RawDescriptionHelpFormatter
)
subparsers = parser.add_subparsers(dest='command', required=True, help='Operation to perform')

# load subcommand
load_parser = subparsers.add_parser('load', help='Load CSV into warehouse')
load_parser.add_argument('file', type=Path, help='Path to CSV file (must exist)')
load_parser.add_argument('--table', required=True, help='Target table name (e.g., job_postings_fact)')
load_parser.add_argument('--mode', choices=['append', 'replace', 'upsert'], default='append',
                         help='Load mode (default: append)')

# validate subcommand
validate_parser = subparsers.add_parser('validate', help='Validate job posting data quality')
validate_parser.add_argument('file', type=Path, help='Path to CSV to validate')
validate_parser.add_argument('--date-range', nargs=2, metavar=('START', 'END'), type=validate_date,
                             help='Check dates within range (YYYY-MM-DD format)')
validate_parser.add_argument('--salary-range', type=validate_salary_range,
                             help='Salary bounds (e.g., 50000,150000)')

# transform subcommand
transform_parser = subparsers.add_parser('transform', help='Transform and denormalize data')
transform_parser.add_argument('file', type=Path, help='Source CSV file')
transform_parser.add_argument('--output', type=Path, required=True, help='Output file path')
transform_parser.add_argument('--filter-wfh', action='store_true', help='Keep only work-from-home jobs')
transform_parser.add_argument('--min-salary', type=int, default=0, help='Minimum salary filter (default: 0)')

args = parser.parse_args()

# Dispatch to handlers (shown in actual code)
if args.command == 'load':
    print(f"Loading {args.file} into {args.table} with mode={args.mode}")
elif args.command == 'validate':
    print(f"Validating {args.file}")
    if args.date_range:
        print(f"  Date range: {args.date_range[0]} to {args.date_range[1]}")
    if args.salary_range:
        print(f"  Salary range: ${args.salary_range[0]:,}–${args.salary_range[1]:,}")
elif args.command == 'transform':
    print(f"Transform {args.file} → {args.output} (w
