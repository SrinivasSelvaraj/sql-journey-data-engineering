---
date: 2026-11-02
phase: streaming
topic: Kafka Connect connectors and transformations
---

# Kafka Connect connectors and transformations

*Streaming and distributed processing*

## Concept

Kafka Connect is a distributed framework for moving data into and out of Kafka at scale using reusable plugins called connectors. Source connectors pull data from external systems (databases, APIs, logs) into topics; sink connectors push data from topics into data warehouses, lakes, or applications. Transformations (SMTs—Single Message Transforms) are lightweight, chainable operations that modify records in-flight without requiring custom code, allowing you to flatten nested JSON, mask sensitive fields, or route messages conditionally.

This matters because streaming pipelines must handle continuous, out-of-order data while remaining declarative and maintainable. Without Connect, you'd write custom producers/consumers for each integration, multiplying failure points and operational burden. Without transformations, you either push raw data and transform downstream (cluttering your processing layer) or build transformation logic into connectors themselves (sacrificing reusability). The abstraction breaks when transformations become stateful (windowing, joins) or when you need cross-record context—at that point, you move to Kafka Streams or Flink.

## Practice

**Problem:** You're ingesting job postings from a PostgreSQL table into Kafka, but the source contains a nested `location_details` JSON object and timestamps in ISO-8601 format. You need to flatten the location, extract only the city, convert the timestamp to UNIX milliseconds, and filter out work-from-home roles before they reach the sink.

```sql
-- PostgreSQL source schema (what Connect reads):
SELECT 
  job_id,
  job_title_short,
  salary_year_avg,
  job_work_from_home,
  job_posted_date,
  location_details::jsonb  -- nested: {"city":"NYC","country":"US"}
FROM job_postings_fact;

-- Kafka Connect configuration (source connector + SMTs):
{
  "name": "postgres-job-postings",
  "config": {
    "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
    "connection.url": "jdbc:postgresql://localhost/jobs_db",
    "query": "SELECT job_id, job_title_short, salary_year_avg, job_work_from_home, job_posted_date, location_details FROM job_postings_fact WHERE job_posted_date > ?",
    "transforms": "flattenLocation,extractCity,convertTimestamp,filterWFH",
    
    "transforms.flattenLocation.type": "org.apache.kafka.connect.transforms.Flatten$Value",
    "transforms.flattenLocation.delimiter": "_",
    
    "transforms.extractCity.type": "org.apache.kafka.connect.transforms.ExtractField$Value",
    "transforms.extractCity.field": "location_details_city",
    
    "transforms.convertTimestamp.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
    "transforms.convertTimestamp.field": "job_posted_date",
    "transforms.convertTimestamp.target.type": "unix_ms",
    
    "transforms.filterWFH.type": "org.apache.kafka.connect.transforms.Filter",
    "transforms.filterWFH.filter.condition": "job_work_from_home == false"
  }
}

-- Result in Kafka topic: job_postings
{
  "job_id": 123,
  "job_title_short": "Data Engineer",
  "salary_year_avg": 95000,
  "job_posted_date": 1672531200000,
  "location_details_city": "NYC"
}
```

## Notes

- **Chain order matters:** SMTs execute sequentially; if you filter before flattening, you can't reference flattened fields in the filter condition. Order transforms from least to most selective.
- **Stateless only:** SMTs have zero state across messages. Use Kafka Streams for deduplication, windowing, or joins; Connect is for schema mapping and routing.
- **Offset management:** Connectors track source offsets. If a transformation fails mid-pipeline, Connect retries from the last committed offset—transformations don't affect offset tracking.
- **Sink connectors need schema compatibility:** Sinks often validate schema before writing (e.g., Avro, Protobuf). Ensure your transformations produce the expected schema and type conversions (strings vs. longs) match downstream expectations.
- **Adjacencies:** Connect bridges event streaming and batch ingestion; learn alongside Avro/Schema Registry (for schema evolution), Kafka Streams (for stateful logic), and exactly-once semantics (idempotent sink connectors prevent duplicates).
