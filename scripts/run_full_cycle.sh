#!/usr/bin/env bash
set -euo pipefail

# Runs a full 3-measure consciousness cycle:
#   Measure 1 + Café → Measure 2 + Café → Measure 3 + Café + Introspection
#
# Usage:
#   ./scripts/run_full_cycle.sh "1000 personas"
#
# Reads measures from a file (one per line, tab-separated: title\tdescription).
# If no file is provided, prompts interactively.
#
# Environment:
#   CLAUDE_API_KEY   — Required.
#   MEASURES_FILE    — Optional. Path to file with measures (default: interactive).
#   LLM_CONCURRENCY  — Optional. Default: 20.

if [ -z "${CLAUDE_API_KEY:-}" ]; then
  echo "ERROR: CLAUDE_API_KEY is not set."
  exit 1
fi

POPULATION="${1:-}"
MEASURES_FILE="${MEASURES_FILE:-}"
CONCURRENCY="${LLM_CONCURRENCY:-20}"

if [ -z "${POPULATION}" ]; then
  echo "Usage: ./scripts/run_full_cycle.sh \"Population Name\""
  echo ""
  echo "Optional env vars:"
  echo "  MEASURES_FILE=path/to/measures.tsv  (tab-separated: title\\tdescription)"
  echo "  LLM_CONCURRENCY=20"
  exit 1
fi

run_measure() {
  local num=$1
  local title=$2
  local description=$3

  echo ""
  echo "========================================"
  echo "=== MEDIDA ${num}/3: ${title}"
  echo "========================================"
  echo ""

  mix sim.run \
    --title "${title}" \
    --description "${description}" \
    --population "${POPULATION}" \
    --cafe \
    --concurrency "${CONCURRENCY}"
}

if [ -n "${MEASURES_FILE}" ] && [ -f "${MEASURES_FILE}" ]; then
  echo "Reading measures from: ${MEASURES_FILE}"
  i=1
  while IFS=$'\t' read -r title description; do
    [ -z "${title}" ] && continue
    run_measure $i "${title}" "${description}"
    i=$((i + 1))
    [ $i -gt 3 ] && break
  done < "${MEASURES_FILE}"
else
  echo "=== Full 3-Measure Consciousness Cycle ==="
  echo "Population: ${POPULATION}"
  echo "Concurrency: ${CONCURRENCY}"
  echo ""
  echo "Enter 3 measures (the 3rd will trigger introspection):"
  echo ""

  for i in 1 2 3; do
    echo "--- Measure ${i}/3 ---"
    read -p "Title: " title
    read -p "Description: " description
    run_measure $i "${title}" "${description}"
  done
fi

echo ""
echo "========================================"
echo "=== CYCLE COMPLETE ==="
echo "========================================"
echo ""

# Show summary
sqlite3 population_simulator_dev.db "
SELECT 'Measures: ' || COUNT(*) FROM measures;
SELECT 'Decisions: ' || COUNT(*) FROM decisions;
SELECT 'Café sessions: ' || COUNT(*) FROM cafe_sessions;
SELECT 'Café effects: ' || COUNT(*) FROM cafe_effects;
SELECT 'Introspections: ' || COUNT(*) FROM actor_summaries;
"
