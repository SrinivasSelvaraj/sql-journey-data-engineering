---
date: 2026-10-19
phase: streaming
topic: Flink side outputs: routing events to multiple sinks
---

# Flink side outputs: routing events to multiple sinks

*Streaming and distributed processing*

## Concept

Flink side outputs let you route events to multiple destinations based on conditional logic, without materializing intermediate datasets. Instead of filtering data after it leaves the pipeline, you tag events at the source operator and split them into labeled outputs—each with its own sink. This is critical when you need different subsets of the same stream to go to different systems (e.g., high-value alerts to Slack, all events to Kafka, data quality failures to a dead-letter queue).

Without side outputs, you'd either run multiple independent jobs (wasteful and hard to keep synchronized) or write all data to one place and re-filter downstream. Side outputs let a single operator partition work efficiently, reducing latency and operational complexity. The split happens *inside* the task, so you avoid replay and maintain ordering guarantees per output.

Side outputs are most valuable when filtering rules are complex, partition cardinality is small-to-medium (typically 2–5 outputs), or when you need low-latency routing with exactly-once semantics. They integrate tightly with Flink's checkpointing model, so rerouted events maintain exactly-once guarantees.

## Practice

**Problem:** Stream job postings. Route fully-remote, high-salary postings (≥$120k/year) to a "premium_leads" sink; all postings to a "raw_feed" sink; and postings with missing salary data to a "data_quality_issues" sink. Maintain event order within each output.

```sql
-- Logical routing applied in the source operator (pseudocode for the Flink job):

CREATE STREAM job_postings_side_outputs AS
SELECT 
  job_id, 
  job_title_short, 
  salary_year_avg, 
  job_work_from_home, 
  job_posted_date, 
  job_location,
  CASE 
    WHEN salary_year_avg IS NULL THEN 'data_quality_issues'
    WHEN job_work_from_home = TRUE AND salary_year_avg >= 120000 THEN 'premium_leads'
    ELSE 'raw_feed'
  END AS output_tag
FROM job_postings_fact;

-- In Java/Scala Flink code:
-- OutputTag<JobPosting> premiumLeadsTag = new OutputTag<>("premium_leads"){};
-- OutputTag<JobPosting> dqIssuesTag = new OutputTag<>("data_quality_issues"){};
-- 
-- ProcessFunction.processElement() evaluates routing logic and calls:
-- context.output(premiumLeadsTag, event);  // for high-value remote jobs
-- context.output(dqIssuesTag, event);      // for nulls
-- (implicit main output for raw_feed via collect() or context.output())
```

## Notes

- **Mistake:** Using side outputs as a general-purpose branching tool for 10+ outputs—this becomes hard to manage. Use broadcast state or downstream branching for complex fan-out.
- **Order guarantees:** Side outputs preserve the order of events *within* each tag, but relative order across tags is not guaranteed unless all tags are derived from the same operator.
- **Connected to:** Broadcast state (distributing config to partitions), splits in DataStream API, and the broader pattern of "late binding" routing decisions close to the source to minimize data movement.
- **Dead-letter pattern:** Side outputs naturally implement dead-letter queues; send malformed or suspicious records to a separate sink for replay or investigation without blocking the main pipeline.
- **Revisit:** How side outputs interact with watermarks and allowed lateness; side outputs don't emit watermarks by default, so you may need custom logic to propagate timing metadata to downstream sinks.
