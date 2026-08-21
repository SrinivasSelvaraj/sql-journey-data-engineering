---
date: 2026-08-21
phase: modelling
topic: Document databases: when embedding beats joining
---

# Document databases: when embedding beats joining

*Data modelling and warehousing*

## Concept

Document databases (MongoDB, DynamoDB, Firestore) often embed related data as nested objects or arrays rather than normalize it into separate tables. This works because: (1) you retrieve the whole document at once, avoiding N+1 queries; (2) your query engine doesn't need to join, making reads faster; (3) the schema is self-documenting—the shape of the data tells you what belongs together.

The tradeoff is write complexity and storage: if you embed a `company` object inside every job posting, and a company's name changes, you update many documents. Embedding wins when reads vastly outnumber writes, when you almost always need the related data together, and when the embedded data is small or rarely changes. It fails when you need to query or update the embedded data independently, or when denormalization causes massive duplication.

In relational databases, you'd normalize this into `job_postings` and `companies` tables and join them. In document databases, you'd likely embed company details inside each job document. The choice depends on your access patterns: if 90% of reads are "get me the full job posting with company info," embedding wins. If you frequently filter by company properties or update company names, normalization wins.

## Practice

**Problem:** You're designing a job posting collection. Each posting needs the full company details (name, industry, employee count, headquarters location). In a relational warehouse, you'd have `job_postings_fact` and `companies_dim` with a foreign key. As a document database, should you embed the company object or reference it?

**Solution:** Embed the company object if access patterns favor full job postings with context:

```sql
-- Document database schema (MongoDB/pseudo-syntax)
db.job_postings.insertOne({
  _id: ObjectId("..."),
  job_id: "JOB_12345",
  job_title_short: "Data Engineer",
  salary_year_avg: 125000,
  job_work_from_home: true,
  job_posted_date: ISODate("2024-01-15"),
  job_location: "San Francisco, CA",
  company: {
    company_id: "COMP_789",
    company_name: "TechCorp",
    company_industry: "Software",
    company_size: 5000,
    company_hq_location: "San Francisco, CA"
  }
})

-- Query: find all remote Data Engineer roles with salary > 100k
db.job_postings.find({
  job_title_short: "Data Engineer",
  job_work_from_home: true,
  salary_year_avg: { $gt: 100000 }
})
-- Returns: full document with embedded company data, no join needed
```

If you instead needed to update company details atomically across all postings or frequently filter by company properties independent of job title, you'd reference the company by ID instead of embedding.

## Notes

- **Denormalization tax**: Embedding means storing redundant data. If a company appears in 500 job postings and you update its name, you update 500 documents. Use embedding only when embedded data changes rarely or you accept eventual consistency.
- **Self-documenting schemas**: A well-structured document schema is discoverable—teammates can see what fields belong together without asking. This is a feature, not a bug. Pair it with schema documentation (JSON schema, Pydantic models) so the shape is canonical.
- **Hybrid approach**: Many systems embed *some* fields (company name, location) but reference others (company_id for joins to a separate company table). Choose based on query cardinality: embed if you need it >80% of the time.
- **Warehouse vs. operational DB**: Relational data warehouses normalize for storage efficiency and analytical queries; document databases optimize for single-document retrieval. Don't force one paradigm onto the other.
- **Revisit: aggregation pipelines and faceted search**: Once you embed data, querying across embedded fields requires aggregation frameworks (MongoDB's `$lookup`, `$unwind`, `$group`). Understand these before assuming embedding eliminates joins entirely.
