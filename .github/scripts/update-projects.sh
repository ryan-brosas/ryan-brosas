#!/usr/bin/env bash
# Fetches public repos and regenerates the "Things I've Built / Touched" section
# in README.md between <!--START_SECTION:projects--> and <!--END_SECTION:projects-->
#
# Exit 0 = README changed (caller should commit)
# Exit 1 = no change

set -euo pipefail

GITHUB_USER="${GITHUB_USER:-ryan-brosas}"
README="${GITHUB_WORKSPACE:-$(dirname "$0")/../../}/README.md"
TOKEN="${GITHUB_TOKEN:-}"

if [[ ! -f "$README" ]]; then
  echo "ERROR: README.md not found at $README" >&2
  exit 1
fi

# Build auth header
AUTH_HEADER=()
if [[ -n "$TOKEN" ]]; then
  AUTH_HEADER=(-H "Authorization: Bearer $TOKEN")
fi

# Fetch repos — sort by updated, 100 per page
RESPONSE=$(curl -sS "${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"}" \
  "https://api.github.com/users/${GITHUB_USER}/repos?per_page=100&sort=updated&direction=desc")

# Validate response
if ! echo "$RESPONSE" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "ERROR: GitHub API did not return an array. Response:" >&2
  echo "$RESPONSE" | head -20 >&2
  exit 1
fi

# Filter: no forks, no archived, skip readme repo, skip .github repo
# Sort by updated_at descending (already sorted by API, but re-sort for safety)
# Generate markdown lines
LINES=$(echo "$RESPONSE" | jq -r '
  [.[] | select(.fork == false and .archived == false and .name != "ryan-brosas" and .name != ".github")]
  | sort_by(.updated_at) | reverse
  | .[]
  | "- [" + .name + "](" + .html_url + ") — " +
    (if .description and .description != "" then .description else "No description" end) +
    " — stars: " + (.stargazers_count | tostring)
')

if [[ -z "$LINES" ]]; then
  echo "WARNING: No repos found after filtering." >&2
  LINES="- No public repositories found"
fi

# Build the replacement block
NEW_SECTION="<!--START_SECTION:projects-->
${LINES}
<!--END_SECTION:projects-->"

# Replace content between markers (inclusive) in README
# Use awk for portability
NEW_README=$(awk -v new="$NEW_SECTION" '
  /<!--START_SECTION:projects-->/ { print new; skip=1; next }
  /<!--END_SECTION:projects-->/  { skip=0; next }
  !skip { print }
' "$README")

# Compare
if diff -q <(cat "$README") <(echo "$NEW_README") >/dev/null 2>&1; then
  echo "No changes to README projects section."
  exit 1
fi

# Write new README
echo "$NEW_README" > "$README"
echo "README projects section updated."
exit 0
