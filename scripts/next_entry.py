#!/usr/bin/env python3
"""Write today's entry stub for the next uncovered topic in the curriculum.

Reads curriculum.json, scans log/ for what's already been covered, and writes
a stub for the first topic that hasn't been. Deterministic, offline, no
network calls. Safe to re-run — exits without writing if today's file exists.
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


def slugify(text):
    text = text.lower()
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")[:60]


def covered_topics():
    """Every topic already written up, read from entry frontmatter."""
    found = set()
    for path in LOG_DIR.rglob("*.md"):
        try:
            head = path.read_text(encoding="utf-8")[:600]
        except OSError:
            continue
        match = re.search(r"^topic:\s*(.+)$", head, re.MULTILINE)
        if match:
            found.add(match.group(1).strip())
    return found


def next_topic(curriculum, done):
    for phase in curriculum["phases"]:
        for topic in phase["topics"]:
            if topic not in done:
                return phase, topic
    return None, None


def render(phase, topic, today):
    return f"""---
date: {today.isoformat()}
phase: {phase['id']}
topic: {topic}
---

# {topic}

*{phase['name']}*

## Concept

<!-- Read up on this, then explain it here in your own words.
     What is it, when does it matter, what breaks without it. -->

## Practice

<!-- The problem you set yourself, and the schema or setup it needs. -->

## Solution

```
-- TODO
```

## Notes

<!-- What tripped you up. What you'd look up again. -->
"""


def emit(key, value):
    target = os.environ.get("GITHUB_OUTPUT")
    if target:
        with open(target, "a", encoding="utf-8") as fh:
            fh.write(f"{key}={value}\n")
    else:
        print(f"{key}={value}")


def main():
    today = datetime.now(timezone.utc).date()

    with CURRICULUM.open(encoding="utf-8") as fh:
        curriculum = json.load(fh)

    # One entry per day. Guard on the date, not the path — the filename carries
    # the topic slug, so a path check would happily write a second topic on a
    # retry instead of skipping.
    if any(LOG_DIR.rglob(f"{today.isoformat()}-*.md")):
        print(f"An entry already exists for {today}, nothing to do.", file=sys.stderr)
        emit("changed", "false")
        return 0

    done = covered_topics()
    phase, topic = next_topic(curriculum, done)

    if topic is None:
        print("Curriculum complete. Add more topics to curriculum.json.", file=sys.stderr)
        emit("changed", "false")
        return 0

    out_path = LOG_DIR / phase["id"] / f"{today.isoformat()}-{slugify(topic)}.md"

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render(phase, topic, today), encoding="utf-8")

    remaining = sum(len(p["topics"]) for p in curriculum["phases"]) - len(done) - 1
    print(f"Wrote {out_path}  ({remaining} topics remaining)", file=sys.stderr)

    emit("changed", "true")
    emit("message", f"Add entry: {topic}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
