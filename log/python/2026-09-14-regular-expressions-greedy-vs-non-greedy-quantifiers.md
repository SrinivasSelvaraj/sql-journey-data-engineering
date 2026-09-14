---
date: 2026-09-14
phase: python
topic: Regular expressions: greedy vs non-greedy quantifiers
---

# Regular expressions: greedy vs non-greedy quantifiers

*Python for data engineering*

## Concept

A greedy quantifier (e.g., `*`, `+`, `{n,}`) matches as much as possible; a non-greedy quantifier (e.g., `*?`, `+?`, `{n,}?`) matches as little as possible while still allowing the overall pattern to succeed. In data pipelines, this distinction is critical when extracting structured fields from semi-structured text—a greedy match can swallow delimiters or span multiple logical units, corrupting your parsed data.

For example, extracting job titles from a string like `"Senior Data Engineer | Full-time | Remote"` with the pattern `(.+)\|` will greedily capture everything up to the *last* pipe character, not the first. This breaks downstream validation and type safety. Non-greedy matching (`(.+?)\|`) stops at the first delimiter, preserving data integrity and making your regex predictable.

In typed, testable pipelines, greedy/non-greedy behavior is invisible until it silently produces wrong output on edge cases—vacancies with multiple delimiters, salary ranges with hyphens, or location strings with parentheses. Choosing the right quantifier upfront is defensive programming.

## Practice

**Problem:** Extract the job title and salary range from unstructured job posting text like `"Senior Data Engineer (Python/SQL) | $120k–$160k/year | NYC"`. Write a SQL query that uses regex to parse `job_title_short` and compute `salary_year_avg` as the midpoint of the range, handling cases where the salary may appear anywhere before the pipe delimiters.

```sql
WITH parsed AS (
  SELECT
    job_id,
    -- Non-greedy capture: stop at first pipe (title is before first |)
    REGEXP_SUBSTR(job_postings_fact.job_location, '^(.+?)\s*\|', 1, 1, NULL, 1) AS extracted_title,
    -- Non-greedy capture: match first number, then hyphen, then second number
    REGEXP_SUBSTR(job_location, '\$(\d+)k?–\$?(\d+)k?', 1, 1, NULL, 1)::INT AS salary_min,
    REGEXP_SUBSTR(job_location, '\$(\d+)k?–\$?(\d+)k?', 1, 1, NULL, 2)::INT AS salary_max
  FROM job_postings_fact
)
SELECT
  job_id,
  TRIM(extracted_title) AS job_title_short,
  ROUND((salary_min + salary_max) / 2.0) AS salary_year_avg
FROM parsed
WHERE extracted_title IS NOT NULL;
```

## Notes

- **Greedy vs. non-greedy is invisible in passing tests:** a greedy `.*` might work on 90% of rows and fail silently on edge cases; always test regex against the full distribution of your input, not just happy paths.
- **Anchors and boundaries prevent most greedy problems:** `^`, `$`, `\b`, and explicit delimiters are often better than relying on non-greedy quantifiers alone—be explicit about what stops a match.
- **Non-greedy doesn't mean "shortest possible string":** `a.+?b` in `axxxbyyb` matches `axxxb`, not `ab`; the regex engine still respects the full pattern, just takes the smallest leap at that quantifier.
- **Connects to:** lookahead/lookbehind assertions (`(?=...)`, `(?<!...)`) which offer finer control than quantifiers alone; also atomic grouping in engines that support it.
- **Revisit when:** adding regex extraction to a pipeline; always pair with type hints (`Optional[str]`, `int`) and unit tests covering multi-delimiter, null, and malformed input cases.
