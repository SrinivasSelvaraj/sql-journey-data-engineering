---
date: 2026-10-18
phase: streaming
topic: Spark StreamingQuery: query status and listener patterns
---

# Spark StreamingQuery: query status and listener patterns

*Streaming and distributed processing*

## Concept

A `StreamingQuery` object in Spark Streaming represents an active streaming computation. It provides access to the query's execution state—whether it's running, stopped, or failed—and allows you to attach listeners that react to query-level events (start, progress, termination). This is critical because streaming jobs run continuously in production, and you need real-time visibility into their health without manually polling logs.

Without query status monitoring and listeners, you lose the ability to detect silent failures, track processing latency, or react when a query crashes. For example, a query might silently fail to process data due to a network partition, but if you only check logs periodically, hours of data could be lost. Listeners let you capture metrics and errors the moment they occur, enabling proactive alerting and graceful degradation.

Query status and listeners are especially important in production ETL pipelines where downstream systems depend on fresh data. You can use listeners to emit metrics to monitoring systems, trigger compensating actions on failure, or even restart failed microbatches with backoff logic.

## Practice

**Problem:** You are ingesting job postings into Spark Streaming. You need to monitor the query's progress in real time—specifically, track how many rows are processed per batch and alert if processing falls behind (batch duration exceeds 5 seconds).

```sql
-- Pseudo-code structure for Spark Streaming listener pattern in Python/Scala

# Define a custom listener
class JobProgressListener extends StreamingQueryListener {
  override def onQueryStarted(event: QueryStartedEvent): Unit = {
    println(s"Query started: ${event.id}")
  }
  
  override def onQueryProgress(event: QueryProgressEvent): Unit = {
    val batchDuration = event.progress.batchDuration
    val rowsProcessed = event.progress.numInputRows
    val processingRate = event.progress.processedRowsPerSecond
    
    println(s"Batch: ${rowsProcessed} rows in ${batchDuration}ms")
    
    if (batchDuration > 5000) {
      alertMonitoring(s"SLOW_BATCH: duration=${batchDuration}ms, rows=${rowsProcessed}")
    }
  }
  
  override def onQueryTerminated(event: QueryTerminatedEvent): Unit = {
    if (event.exception.isDefined) {
      alertMonitoring(s"QUERY_FAILED: ${event.exception.get.getMessage}")
    } else {
      println(s"Query terminated normally: ${event.id}")
    }
  }
}

# Attach listener and run streaming query
spark.streams.addListener(new JobProgressListener())

val query = spark
  .readStream
  .schema(jobPostingsSchema)
  .parquet("/data/job_postings_stream")
  .writeStream
  .format("parquet")
  .option("checkpointLocation", "/checkpoints/job_postings")
  .start()

query.awaitTermination()
```

## Notes

- **Listener overhead:** Listeners run synchronously; heavy computations in `onQueryProgress` can slow down microbatch processing. Keep listener logic lightweight and offload work to async threads.

- **Checkpoint state vs. query status:** A query may be running but checkpoints may be lagging behind input arrival rate. Monitor both `batchDuration` and `inputRowsPerSecond` to catch backpressure.

- **Exception handling in listeners:** Exceptions thrown inside a listener do *not* stop the query by default. You must explicitly call `query.stop()` or emit alerts to an external system to trigger remediation.

- **Timestamp interpretation:** `QueryProgressEvent.timestamp` is wall-clock time when the batch completed. Use it to correlate with upstream data ingestion times and detect end-to-end latency.

- **Related patterns:** Consider pairing listeners with write-ahead logs (WAL) for fault tolerance, and with structured logging (e.g., JSON appends) so monitoring dashboards can query query metrics historically.
