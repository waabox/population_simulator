#!/usr/bin/env bash
set -euo pipefail

# Runs a population simulation against an economic measure.
#
# Usage:
#   ./scripts/run_simulation.sh "Description of the economic measure"
#   ./scripts/run_simulation.sh "Description..." --title "Short name" --limit 500 --concurrency 50
#
# Environment:
#   CLAUDE_API_KEY   — Required. Anthropic API key.
#   CLAUDE_MODEL     — Optional. Default: claude-haiku-4-5-20251001
#   LLM_CONCURRENCY  — Optional. Default: 30
#
# Examples:
#   ./scripts/run_simulation.sh "The government removed subsidies for electricity, gas and water."
#   ./scripts/run_simulation.sh "A 30% tax on dollar purchases is established." --limit 100

if [ -z "${CLAUDE_API_KEY:-}" ]; then
  echo "ERROR: CLAUDE_API_KEY is not set."
  echo ""
  echo "  export CLAUDE_API_KEY=sk-ant-..."
  echo "  ./scripts/run_simulation.sh \"Description of the measure\""
  exit 1
fi

if [ $# -eq 0 ]; then
  echo "Usage: ./scripts/run_simulation.sh \"Description of the economic measure\" [options]"
  echo ""
  echo "Options:"
  echo "  --title         Short title for the measure (default: first 60 chars of description)"
  echo "  --limit         Number of actors to evaluate (default: all)"
  echo "  --concurrency   Concurrent LLM calls (default: 30)"
  echo ""
  echo "Examples:"
  echo "  ./scripts/run_simulation.sh \"The government removed subsidies for electricity, gas and water.\""
  echo "  ./scripts/run_simulation.sh \"A 30% tax on dollar purchases is established.\" --limit 500"
  exit 1
fi

DESCRIPTION="$1"
shift

TITLE=""
LIMIT=""
CONCURRENCY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --title)       TITLE="$2"; shift 2 ;;
    --limit)       LIMIT="$2"; shift 2 ;;
    --concurrency) CONCURRENCY="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ -z "${TITLE}" ]; then
  TITLE=$(echo "${DESCRIPTION}" | cut -c1-60)
fi

# Check DB has actors
ACTOR_COUNT=$(echo "SELECT COUNT(*) FROM actors;" | docker exec -i population_simulator-postgres-1 psql -U postgres population_simulator_dev -t 2>/dev/null | tr -d ' ')

if [ "${ACTOR_COUNT}" = "0" ] || [ -z "${ACTOR_COUNT}" ]; then
  echo "No actors in database. Seed first:"
  echo ""
  echo "  ./scripts/download_eph.sh 3 2025"
  echo "  mix sim.seed --n 5000"
  exit 1
fi

echo "=== Population Simulator ==="
echo "Actors in DB: ${ACTOR_COUNT}"
echo "Measure: ${TITLE}"
echo "Description: ${DESCRIPTION}"
[ -n "${LIMIT}" ] && echo "Limit: ${LIMIT} actors" || echo "Limit: all actors"
[ -n "${CONCURRENCY}" ] && echo "Concurrency: ${CONCURRENCY}" || echo "Concurrency: 30 (default)"
echo ""

MIX_ARGS="--title \"${TITLE}\" --description \"${DESCRIPTION}\""
[ -n "${LIMIT}" ] && MIX_ARGS="${MIX_ARGS} --limit ${LIMIT}"
[ -n "${CONCURRENCY}" ] && MIX_ARGS="${MIX_ARGS} --concurrency ${CONCURRENCY}"

eval mix sim.run ${MIX_ARGS}
