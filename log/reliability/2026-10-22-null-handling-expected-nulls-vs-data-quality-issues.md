---
date: 2026-10-22
phase: reliability
topic: Null handling: expected nulls vs data quality issues
---

# Null handling: expected nulls vs data quality issues

*Quality, reliability and the professional layer*

## Concept

Expected nulls are design choices—missing data that *should* be there according to your schema. Data quality issues are unexpected nulls that signal broken upstream processes, incomplete ETL, or corrupted sources. The difference is intent. A job posting with no remote work policy recorded (null in job_work_from_home) might be expected because the source system doesn't always capture it. But a job_posted_date of null is almost certainly a quality failure—jobs must have a posting date to exist meaningfully in your fact table.

Distinguishing these matters because they require opposite actions. Expected nulls need explicit documentation, sensible defaults, or nullable columns that you monitor for volume shifts. Quality issues need alerts, quarantine logic, and root cause investigation. Without this distinction, you either suppress legitimate signals (ignoring real data quality problems) or create alert fatigue (escalating every expected absence as a crisis).

The professional layer means owning the pipeline's reliability contract: committing to SLAs about data completeness, knowing which nulls are acceptable, catching unexpected ones before they propagate downstream, and communicating these decisions to stakeholders. Junior engineers often treat all nulls as equivalent; trusted owners know the difference and document it.

## Practice

**Problem:** Your job_postings_fact table shows 12% of salary_year_avg values as null, but only 0.3% of job_posted_date values are null. Last week the salary figure was 8%. You need to detect whether the salary increase is expected or a quality issue, and handle each appropriately.

```sql
-- Separate expected from unexpected nulls
with quality_checks as (
  select
    current_date as check_date,
    count(*) as total_records,
    countif(job_posted_date is null) as posted_date_nulls,
    countif(salary_year_avg is null) as salary_nulls,
    countif(salary_year_avg is null) / count(*) as salary_null_pct,
    countif(job_work_from_home is null) as remote_nulls
  from job_postings_fact
  where job_posted_date >= current_date - 7
)
select
  check_date,
  total_records,
  posted_date_nulls,
  case
    when posted_date_nulls > 0 then 'ALERT: unexpected null in required field'
    else 'OK'
  end as posted_date_quality,
  salary_null_pct,
  case
    when salary_null_pct > 0.10 then 'WARN: salary nulls above 10% threshold'
    when salary_null_pct between 0.05 and 0.10 then 'OK: within expected range'
    else 'INVESTIGATE: salary null rate dropped'
  end as salary_quality,
  remote_nulls,
  'EXPECTED: remote work not always captured in source' as remote_note
from quality_checks;
```

## Notes

- **Confusing "null" with "missing"**: Not every null is a gap. Document your schema's intent: which columns *must* have values, which *can* legitimately be unknown, and how to distinguish them in code.

- **Threshold blindness**: Don't just check for nulls; establish acceptable ranges. A 2% shift might be noise; a 10% jump is actionable. Thresholds embed your data contracts.

- **Connects to observability**: This is where metrics and monitoring become critical. Track null counts, percentages, and drift by source and column. Integrate with your alerting layer so expected nulls don't trigger alarms.

- **Common mistake**: Handling nulls inconsistently across the pipeline. If salary_year_avg nulls are coalesced to 0 in one transform and left null in another, downstream consumers will be confused. Decide once, document it, enforce it.

- **Worth revisiting**: How your warehouse models unknown data (NULL vs. placeholder values like -1 or "UNKNOWN"), and how that decision cascades into BI layer expectations and end-user confusion.
