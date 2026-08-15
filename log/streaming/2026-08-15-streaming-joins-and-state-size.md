---
date: 2026-08-15
phase: streaming
topic: Streaming joins and state size
---

# Streaming joins and state size

*Streaming and distributed processing*

## Concept

A streaming join combines two unbounded streams or a stream with state, but unlike batch joins, you cannot simply hold all historical data in memory. The challenge is deciding *how long* to retain state—the window of time during which events from one stream can match events from another. If you keep state too short, valid late-arriving records miss their join partner. If you keep it too long, memory grows without bound and queries become unresponsive.

State size explodes when joining high-volume streams without thoughtful retention policies. For example, joining user activity events with session events requires you to buffer sessions in state until all activity events for that session arrive. Without a time-based eviction policy, sessions from months ago still occupy memory. The trade-off is between correctness (catching all valid matches) and resource efficiency (not running out of memory).

In production, you must make an explicit choice: grace period (how late is "too late" for an event), watermarking (tracking progress of time), and state backend configuration (what gets serialized and where). Without these, the pipeline either silently drops valid joins or crashes under memory pressure.

## Practice

**Problem:** You have a stream of job postings and a separate stream of job application submissions. You need to join them so that each application knows the salary and work-from-home status of the job it applied to. Applications can arrive up to 7 days after the job is posted. State must not grow indefinitely.

```sql
SELECT 
    app.application_id,
    app.job_id,
    app.applicant_id,
    app.application_timestamp,
    jp.job_title_short,
    jp.salary_year_avg,
    jp.job_work_from_home
FROM job_applications_stream AS app
LEFT JOIN job_postings_fact FOR SYSTEM_TIME AS OF app.application_timestamp AS jp
    ON app.job_id = jp.job_id
WHERE app.application_timestamp BETWEEN jp.job_posted_date 
    AND jp.job_posted_date + INTERVAL 7 DAY
;
```

Alternatively, with explicit state retention in Flink/Spark:
```sql
SELECT 
    app.application_id,
    app.job_id,
    jp.job_title_short,
    jp.salary_year_avg
FROM job_applications_stream AS app
JOIN job_postings_stream AS jp
    ON app.job_id = jp.job_id
    AND app.application_timestamp BETWEEN jp.job_posted_date 
        AND jp.job_posted_date + INTERVAL 7 DAY
;
-- Configure state TTL: 7 days + 1 day grace period (8 days total)
```

## Notes

- **State TTL is not optional:** Always set an explicit time-to-live on join state, even if it means dropping some late-arriving matches. Unbounded state is a production incident waiting to happen.
- **Watermarks drive correctness:** If you don't emit watermarks that signal "no events before time X will arrive," the stream processor cannot know when to close a join window and emit final results.
- **Asymmetric retention:** One stream may need much longer retention than the other. Design separately; don't default to "same TTL for both sides."
- **Connects to:** windowed aggregations (which also face state explosion), late-arriving data handling, and exactly-once semantics (which get harder when state is large and checkpoints are frequent).
- **Revisit:** Compare stream-to-stream joins versus stream-to-batch (dimensional) joins; the latter sidesteps state size issues but introduces lookup latency and staleness concerns.
