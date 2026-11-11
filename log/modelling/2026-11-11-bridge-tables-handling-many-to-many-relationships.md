---
date: 2026-11-11
phase: modelling
topic: Bridge tables: handling many-to-many relationships
---

# Bridge tables: handling many-to-many relationships

*Data modelling and warehousing*

## Concept

A bridge table (also called a junction or linking table) resolves many-to-many relationships by breaking them into two one-to-many relationships. Without it, you either denormalize data (storing repeated rows or comma-separated lists), which breaks queries and wastes storage, or you force artificial constraints that don't reflect reality.

Consider a job posting that requires multiple skills, and each skill is needed across many job postings. A direct column in `job_postings_fact` cannot store multiple skills cleanly. A bridge table `job_posting_skills` with columns `(job_id, skill_id, proficiency_level)` lets you query "which jobs need Python?" or "how many jobs require this skill set?" without string parsing or row duplication.

Bridge tables are essential whenever your fact table has a many-to-many dependency. They keep your schema normalized, enable efficient filtering and aggregation, and make column meaning explicit to future users of your warehouse.

## Practice

**Problem:** A job posting can require multiple skills (Python, SQL, Tableau), and each skill appears across many job postings. Your current `job_postings_fact` has no way to store this relationship. You need to find all jobs requiring both Python *and* SQL.

```sql
-- Bridge table structure
CREATE TABLE job_posting_skills (
    job_id INT,
    skill_id INT,
    proficiency_level VARCHAR(50),
    PRIMARY KEY (job_id, skill_id),
    FOREIGN KEY (job_id) REFERENCES job_postings_fact(job_id),
    FOREIGN KEY (skill_id) REFERENCES skills_dim(skill_id)
);

-- Query: jobs requiring both Python AND SQL
SELECT DISTINCT j.job_id, j.job_title_short, j.job_location
FROM job_postings_fact j
INNER JOIN job_posting_skills jps1 
    ON j.job_id = jps1.job_id 
    AND jps1.skill_id = (SELECT skill_id FROM skills_dim WHERE skill_name = 'Python')
INNER JOIN job_posting_skills jps2 
    ON j.job_id = jps2.job_id 
    AND jps2.skill_id = (SELECT skill_id FROM skills_dim WHERE skill_name = 'SQL')
WHERE j.job_posted_date >= '2024-01-01';
```

## Notes

- **Composite primary keys matter:** Bridge table PKs should combine both foreign keys to prevent duplicate relationships and enable efficient joins.
- **Don't skip the bridge table:** Storing "Python, SQL, Tableau" as a single string or JSON field defeats normalization; you cannot filter or aggregate on individual skills without expensive parsing.
- **Connects to:** Dimensional modeling (Kimball), slowly changing dimensions (if skills or proficiency levels evolve), and cardinality analysis—understanding your many-to-many cardinality shapes index strategy.
- **Watch for over-normalization:** Not every one-to-many needs a bridge table; use them only when cardinality is genuinely many-to-many. A job's primary location (one location, many jobs) doesn't need a bridge.
- **Documentation wins:** Label bridge tables clearly in schema docs. New team members often misinterpret them as facts; a comment like "lookup table; join to fact on job_id" prevents confusion.
