---
date: 2026-08-21
phase: modelling
topic: Graph data modelling: property graphs and RDF
---

# Graph data modelling: property graphs and RDF

*Data modelling and warehousing*

## Concept

Property graphs and RDF represent data as interconnected entities and relationships rather than flat tables. In a property graph, nodes (entities) carry attributes and edges (relationships) connect them with their own properties; RDF uses triples (subject–predicate–object) to make every relationship explicit and queryable. Both are powerful for domains where relationships matter as much as attributes: social networks, knowledge bases, supply chains, and skill taxonomies.

This matters when your star schema starts straining under many-to-many relationships. For example, a job posting belongs to multiple skill categories, locations, and companies—flattening these into rows creates redundancy and makes it hard to ask "which skills co-occur in well-paid roles?" without complex joins or denormalization. Without a graph model, you either duplicate data or write expensive queries that obscure intent.

Graph models break down when you need ACID transactions across many nodes, when your team lacks query tooling (SQL is universal; Cypher or SPARQL are not), or when you optimize for analytical speed over relationship navigation. They also introduce schema fragility—without clear cardinality and type constraints, properties drift and queries become fragile.

## Practice

**Problem:** Your job_postings_fact table has a job_skills column that stores comma-separated skill names. You need to find the average salary for roles requiring both Python AND SQL, and count how many such postings exist in each location—without string parsing.

**Solution:**

```sql
-- Normalize into a property graph structure
CREATE TABLE skill (
  skill_id INT PRIMARY KEY,
  skill_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE job_skill (
  job_id INT NOT NULL,
  skill_id INT NOT NULL,
  PRIMARY KEY (job_id, skill_id),
  FOREIGN KEY (skill_id) REFERENCES skill(skill_id),
  FOREIGN KEY (job_id) REFERENCES job_postings_fact(job_id)
);

-- Query: jobs requiring both Python AND SQL, grouped by location
SELECT
  j.job_location,
  COUNT(DISTINCT j.job_id) AS posting_count,
  ROUND(AVG(j.salary_year_avg), 0) AS avg_salary
FROM job_postings_fact j
INNER JOIN job_skill js_python 
  ON j.job_id = js_python.job_id 
  AND js_python.skill_id = (SELECT skill_id FROM skill WHERE skill_name = 'Python')
INNER JOIN job_skill js_sql 
  ON j.job_id = js_sql.job_id 
  AND js_sql.skill_id = (SELECT skill_id FROM skill WHERE skill_name = 'SQL')
GROUP BY j.job_location
ORDER BY avg_salary DESC;
```

## Notes

- **Avoid the comma-separated trap:** Denormalizing relationships into strings or arrays saves initial ETL effort but makes filtering, aggregation, and maintenance exponentially harder. Normalize early.
- **Schema clarity requires documented cardinality:** State plainly whether one job has many skills, one skill has many jobs, etc. Use data dictionaries or inline comments so teammates don't guess.
- **Property graphs (Cypher, Neo4j) excel at traversal queries** (e.g., "skills required by this role + companies hiring for it + roles those companies are also posting"); RDF/SPARQL is semantic and machine-readable but heavier operationally.
- **Start with relational normalization, graduate to graph tools only when JOIN complexity or query latency justifies the operational cost** of another system.
- **Revisit: slowly changing dimensions** for skills (skill demand evolves), and **bridge tables** as the practical SQL pattern for many-to-many relationships before adopting full graph tooling.
