---
date: 2026-09-27
phase: streaming
topic: Co-partitioning requirements for keyed joins
---

# Co-partitioning requirements for keyed joins

*Streaming and distributed processing*

## Concept

Co-partitioning ensures that records with the same join key arrive at the same partition in both input streams or tables. Without it, a keyed join will miss matches because the join operator on partition A cannot see records from partition B, even if they share the same key. In Kafka-based systems (Flink, Spark Structured Streaming), this means both topics must have the same number of partitions and use the same partitioner function; in data warehouses, it means pre-sorting and bucketing by the join key before the join operation.

The cost of ignoring co-partitioning is silent data loss: your query executes without error but produces incomplete or zero results. This is especially dangerous in streaming because failures are harder to detect—a join simply stops matching after a rebalance or repartition. Co-partitioning is *required* for correctness in any keyed aggregation or join where you cannot afford a full shuffle; it trades upfront partitioning discipline for runtime correctness and performance.

## Practice

**Problem:** You are joining `job_postings_fact` with a `candidate_applications` stream on `job_id`. Both sources arrive via Kafka. Applications are arriving out-of-order and late, and you need to emit a result stream of (job_id, job_title_short, application_count) every time a new application arrives for a job posted in the last 30 days. Without co-partitioning, applications for job_id=42 might land on partition 3 while the job posting lands on partition 1, and the join will never fire.

```sql
-- Assume both Kafka topics are created with the same partition count and key strategy
-- Topic: job_postings (partitions=8, key=job_id)
-- Topic: candidate_applications (partitions=8, key=job_id)

-- In Spark Structured Streaming with Kafka source
val jobPostings = spark.readStream
  .format("kafka")
  .option("kafka.bootstrap.servers", "localhost:9092")
  .option("subscribe", "job_postings")
  .load()
  .select(from_json(col("value").cast("string"), "job_id INT, job_title_short STRING, job_posted_date DATE").alias("jp"))
  .select("jp.*")

val applications = spark.readStream
  .format("kafka")
  .option("kafka.bootstrap.servers", "localhost:9092")
  .option("subscribe", "candidate_applications")
  .load()
  .select(from_json(col("value").cast("string"), "job_id INT, applicant_id INT").alias("app"))
  .select("app.*")

-- Co-partitioned join: both streams keyed on job_id
val result = jobPostings
  .join(
    applications,
    expr("jobPostings.job_id = applications.job_id"),
    "inner"
  )
  .groupBy("job_id", "job_title_short")
  .agg(count("applicant_id").alias("application_count"))
  .writeStream
  .format("console")
  .start()
```

## Notes

- **Partition count mismatch is silent:** If topics have different partition counts, Kafka will not error, but joins become unreliable. Always verify `num.partitions` before deployment.
- **Rebalances break locality:** When a consumer group rebalances, partitions are reassigned; ensure your join operator is *stateless per partition* so it can migrate safely without losing in-flight state.
- **Repartitioning defeats co-partitioning:** Calling `.repartition()` or `.shuffle()` on one input after reading breaks the guarantee; do this *before* the join or not at all.
- **Connects to windowing and state stores:** Co-partitioning is a prerequisite for efficient stateful operations; without it, your state backend cannot be partitioned by key and becomes a bottleneck.
- **Test with clock skew:** Co-partitioning ensures *physical* locality, but lateness and out-of-order arrival are orthogonal; use watermarks and allowed lateness to handle temporal misalignment.
