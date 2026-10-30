---
date: 2026-10-30
phase: cloud
topic: Data transfer between regions and cloud providers
---

# Data transfer between regions and cloud providers

*Cloud platforms and storage*

## Concept

Data transfer between regions and cloud providers incurs egress costs—fees charged when data leaves a region or cloud platform. Major cloud providers (AWS, GCP, Azure) charge little to nothing for ingress but can levy $0.01–$0.20 per GB for egress, making cross-region queries and multi-cloud pipelines surprisingly expensive. This cost structure incentivizes keeping data geographically close to compute and avoiding unnecessary data movement during joins, aggregations, or exports.

Query slowness across regions stems from network latency and bandwidth constraints. A query reading 100 GB from a different region may take minutes longer than local execution, even if the query logic is identical. Without awareness of data locality, you might unknowingly design ETL pipelines that shuffle gigabytes daily—degrading performance while inflating bills.

Understanding egress prevents two failure modes: silent cost explosions (a once-daily export to a data lake spirals into millions per year) and performance puzzles (why does my dashboard query take 30 seconds when the same table in the same region takes 3 seconds?).

## Practice

**Problem:** Your job_postings_fact table is in us-east-1 (AWS). A team in eu-west-1 needs daily salary statistics. A naive approach exports the entire table nightly; this costs ≈$2,000+ monthly if the table is 5 TB. How do you reduce egress?

**Solution:** Materialize aggregates in the source region before transfer, or replicate only the columns and rows needed.

```sql
-- Instead of: SELECT * FROM job_postings_fact (100 GB egress)
-- Create a materialized view in us-east-1, then replicate only the summary

CREATE TABLE job_postings_salary_summary AS
SELECT 
  job_location,
  job_title_short,
  COUNT(*) as posting_count,
  AVG(salary_year_avg) as avg_salary,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_year_avg) as median_salary,
  DATE(job_posted_date) as post_date
FROM job_postings_fact
WHERE salary_year_avg IS NOT NULL
GROUP BY job_location, job_title_short, DATE(job_posted_date);

-- Transfer only this 10 MB summary table to eu-west-1 instead of 5 TB raw data
```

## Notes

- **Egress is asymmetric:** ingress is free or cheap; always pull data toward expensive regions rather than push. Query remotely if possible.
- **Compression matters:** gzip or parquet reduce transfer size by 5–10x; a 500 GB export becomes 50 GB, saving $5 in egress alone.
- **Same-region joins are orders of magnitude faster:** if two tables are in different regions, move one before joining; the network cost of misplaced data exceeds the storage cost of duplication.
- **CloudFront / CDN caching:** for frequently accessed datasets, cache in edge locations; this converts one egress charge into many cheap CDN hits.
- **Adjacent topic:** understand your cloud provider's pricing calculator and run cost projections for new pipelines; the query was slow *and* cost $2,000 because egress and network latency compounded.
