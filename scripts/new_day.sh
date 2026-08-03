#!/usr/bin/env bash

set -euo pipefail

date_value="${1:-$(date +%F)}"
target_file="daily/${date_value}.md"

if [[ -e "$target_file" ]]; then
  echo "Daily note already exists: $target_file"
  exit 0
fi

mkdir -p daily

{
  printf '%s\n' \
    "# Daily Log - ${date_value}" \
    "" \
    "## What I studied" \
    "" \
    "- " \
    "" \
    "## One SQL query or idea" \
    "" \
    '```sql' \
    '-- write one query or note here' \
    '```' \
    "" \
    "## What I learned" \
    "" \
    "- " \
    "" \
    "## Next step tomorrow" \
    "" \
    "- "
} > "$target_file"

echo "Created $target_file"
