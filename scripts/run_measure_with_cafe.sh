#!/usr/bin/env bash
set -euo pipefail

# Runs a measure + café round (group conversations after decisions).
# Introspection auto-triggers every 3rd measure.
#
# Usage:
#   ./scripts/run_measure_with_cafe.sh "Description of the economic measure"
#   ./scripts/run_measure_with_cafe.sh "Description..." --title "Short name" --population "1000 personas"
#
# Environment:
#   CLAUDE_API_KEY   — Required. Anthropic API key.
#   LLM_CONCURRENCY  — Optional. Default: 20

if [ -z "${CLAUDE_API_KEY:-}" ]; then
  echo "ERROR: CLAUDE_API_KEY is not set."
  echo "  export CLAUDE_API_KEY=sk-ant-..."
  exit 1
fi

if [ $# -eq 0 ]; then
  echo "Usage: ./scripts/run_measure_with_cafe.sh \"Description\" [options]"
  echo ""
  echo "Options:"
  echo "  --title         Short title (default: first 60 chars of description)"
  echo "  --population    Population name (default: none, uses all actors)"
  echo "  --concurrency   Concurrent LLM calls (default: 20)"
  echo ""
  echo "Example:"
  echo "  ./scripts/run_measure_with_cafe.sh \"El gobierno anuncia suba del 5% en tarifas\" --population \"1000 personas\""
  exit 1
fi

DESCRIPTION="$1"
shift

TITLE=""
POPULATION=""
CONCURRENCY="${LLM_CONCURRENCY:-20}"

while [ $# -gt 0 ]; do
  case "$1" in
    --title)       TITLE="$2"; shift 2 ;;
    --population)  POPULATION="$2"; shift 2 ;;
    --concurrency) CONCURRENCY="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

[ -z "${TITLE}" ] && TITLE=$(echo "${DESCRIPTION}" | cut -c1-60)

MEASURE_COUNT=$(sqlite3 population_simulator_dev.db "SELECT COUNT(*) FROM measures;" 2>/dev/null || echo "0")
NEXT=$((MEASURE_COUNT + 1))

echo "=== Medida #${NEXT} + Café ==="
echo "Título: ${TITLE}"
echo "Descripción: ${DESCRIPTION}"
[ -n "${POPULATION}" ] && echo "Población: ${POPULATION}"
echo "Concurrency: ${CONCURRENCY}"
if [ $((NEXT % 3)) -eq 0 ]; then
  echo "*** Introspección se disparará automáticamente (medida #${NEXT}) ***"
fi
echo ""

MIX_ARGS="--title \"${TITLE}\" --description \"${DESCRIPTION}\" --cafe --concurrency ${CONCURRENCY}"
[ -n "${POPULATION}" ] && MIX_ARGS="${MIX_ARGS} --population \"${POPULATION}\""

eval mix sim.run ${MIX_ARGS}
