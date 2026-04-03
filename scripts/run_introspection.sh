#!/usr/bin/env bash
set -euo pipefail

# Runs introspection round manually for a population.
# Each actor reflects on recent experiences and updates their autobiographical narrative.
#
# Usage:
#   ./scripts/run_introspection.sh "1000 personas"
#
# Environment:
#   CLAUDE_API_KEY — Required.

if [ -z "${CLAUDE_API_KEY:-}" ]; then
  echo "ERROR: CLAUDE_API_KEY is not set."
  exit 1
fi

POPULATION="${1:-}"

if [ -z "${POPULATION}" ]; then
  echo "Usage: ./scripts/run_introspection.sh \"Population Name\""
  exit 1
fi

echo "=== Introspection Round ==="
echo "Population: ${POPULATION}"
echo ""

mix sim.introspect --run --population "${POPULATION}"
