#!/usr/bin/env python3
"""Write one learning entry for the next uncovered curriculum topic.

Called in a loop by the workflow — each call writes one file and exits.
ENTRIES_PER_DAY controls how many files per calendar day before stopping.
If ANTHROPIC_API_KEY is set, content is AI-generated; otherwise a blank
stub is written so the script stays usable offline.
"""

import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CURRICULUM = ROOT / "curriculum.json"
LOG_DIR = ROOT / "log"

MAX_PER_DAY = int(os.environ.get("ENTRIES_PER_DAY", "7"))
MODEL = "claude-haiku-4-5-20251001"


def slugify(text):
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")[:60]


def covered_topics():
    found = set()
    for path in LOG_DIR.rglob("*.md"):
        try:
            head = path.read_text(encoding="utf-8")[:600]
        except OSError:
            continue
        m = re.search(r"^topic:\s*(.+)$", head, re.MULTILINE)
        if m:
            found.add(m.group(1).strip())
    return found


def todays_count(today):
    return len(list(LOG_DIR.rglob(f"{today.isoformat()}-*.md")))


def next_topic(curriculum, done):
    for phase in curriculum["phases"]:
        for topic in phase["topics"]:
            if topic not in done:
                return phase, topic
    return None, None


def generate_content(phase, topic):
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        return None
    try:
        import anthropic
        client = anthropic.Anthropic(api_key=api_key)
        prompt = f"""You are writing a concise learning entry for a data engineering self-study log.

Topic: {topic}
Phase: {phase['name']} — {phase['goal']}

Write exactly three sections. Output only the markdown sections, no preamble.

## Concept

2–3 focused paragraphs: what it is, when it matters, what breaks without it. Be specific and practical.

## Practice

One concrete problem using this schema:
  job_postings_fact(job_id, job_title_short, salary_year_avg, job_work_from_home BOOLEAN, job_posted_date DATE, job_location)

State the problem, then show the solution in a ```sql block.

## Notes

4–5 bullet points: common mistakes, adjacent topics this connects to, things worth revisiting."""

        msg = client.messages.create(
            model=MODEL,
            max_tokens=1200,
            messages=[{"role": "user", "content": prompt}],
        )
        return msg.content[0].text.strip()
    except Exception as exc:
        print(f"API error: {exc}", file=sys.stderr)
        return None


def render(phase, topic, today, content=None):
    header = f"""---
date: {today.isoformat()}
phase: {phase['id']}
topic: {topic}
---

# {topic}

*{phase['name']}*

"""
    if content:
        return header + content + "\n"
    return header + """## Concept

<!-- Explain it here in your own words. -->

## Practice

```sql
-- TODO
```

## Notes

<!-- What tripped you up. What you would look up again. -->
"""


def emit(key, value):
    # always write to stdout so the workflow loop can parse it
    print(f"{key}={value}")
    target = os.environ.get("GITHUB_OUTPUT")
    if target:
        with open(target, "a", encoding="utf-8") as fh:
            fh.write(f"{key}={value}\n")


def main():
    today = datetime.now(timezone.utc).date()

    if todays_count(today) >= MAX_PER_DAY:
        print(f"Reached {MAX_PER_DAY} entries for {today}.", file=sys.stderr)
        emit("changed", "false")
        return 0

    with CURRICULUM.open(encoding="utf-8") as fh:
        curriculum = json.load(fh)

    done = covered_topics()
    phase, topic = next_topic(curriculum, done)

    if topic is None:
        print("Curriculum complete — add more topics to curriculum.json.", file=sys.stderr)
        emit("changed", "false")
        return 0

    content = generate_content(phase, topic)
    out_path = LOG_DIR / phase["id"] / f"{today.isoformat()}-{slugify(topic)}.md"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render(phase, topic, today, content), encoding="utf-8")

    source = "AI" if content else "stub"
    remaining = sum(len(p["topics"]) for p in curriculum["phases"]) - len(done) - 1
    print(f"Wrote {out_path.name} ({source}, {remaining} remaining)", file=sys.stderr)

    emit("changed", "true")
    emit("message", f"Add entry: {topic}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
