---
date: 2026-08-25
phase: sql
topic: String regex patterns: anchors, character classes and lookahead
---

# String regex patterns: anchors, character classes and lookahead

*SQL for analytics and engineering*

## Concept

Regex patterns in SQL enable powerful text matching beyond simple LIKE operators. **Anchors** (^ and $) pin matches to string boundaries, **character classes** ([a-z], \d, \w) match sets of characters efficiently, and **lookahead** (?=...) asserts conditions without consuming characters—critical for validating formats or extracting precise substrings without over-matching. In analytics, this matters when cleaning messy job titles, validating email formats, or detecting specific skill mentions buried in job descriptions. Without anchors, a pattern like `Senior` matches "Senior" anywhere in a string; with ^Senior, it matches only at the start. Without lookahead, extracting "Python" from "Python 3.8 required" forces you to include the version; lookahead lets you assert "Python" exists before a digit without including it.

Most SQL dialects (PostgreSQL ~, MySQL REGEXP, BigQuery REGEXP_CONTAINS) support regex, but syntax varies—PostgreSQL uses POSIX extended regex (no lookahead by default), while BigQuery/Snowflake use RE2 (lookahead supported). Performance degrades with greedy quantifiers on large datasets; anchors and specific character classes constrain the search space and make queries predictable under load.

## Practice

**Problem:** From job_postings_fact, find all job titles that start with "Senior" (exact word boundary) and are posted after 2023-01-01, excluding any title containing "Intern" or "Associate" anywhere in it.

```sql
SELECT job_id, job_title_short, job_posted_date
FROM job_postings_fact
WHERE job_posted_date > '2023-01-01'
  AND job_title_short ~ '^Senior\s'
  AND job_title_short !~ '(Intern|Associate)'
ORDER BY job_posted_date DESC;
```

**Alternative (BigQuery):**
```sql
SELECT job_id, job_title_short, job_posted_date
FROM job_postings_fact
WHERE job_posted_date > '2023-01-01'
  AND REGEXP_CONTAINS(job_title_short, r'^Senior\s')
  AND NOT REGEXP_CONTAINS(job_title_short, r'(Intern|Associate)')
ORDER BY job_posted_date DESC;
```

## Notes

- **Anchor mistakes:** Forgetting ^ or $ leads to substring matches; `Senior` matches "Senior Developer" AND "Very Senior Developer." Always anchor when matching position matters.
- **Lookahead syntax varies:** PostgreSQL POSIX doesn't support (?=...), but BigQuery, Snowflake, and Redshift (via regex UDFs) do. Check your engine before writing lookahead—fallback to character classes or multi-condition WHERE clauses.
- **Performance risk:** Regex on every row in a 10M-row table is slow. Filter first with indexed columns (job_posted_date, salary ranges) before applying regex on the reduced set.
- **Character class shortcuts:** \d (digits), \w (word chars), \s (whitespace) are dense; `[0-9a-zA-Z_]` is verbose. Use shortcuts for readability and sometimes better optimization.
- **Escape special chars:** In regex, `.`, `*`, `+`, `?`, `[`, `]`, `(`, `)` are metacharacters. Escape them with `\` if matching literally (e.g., `C\+\+` for the language C++).
