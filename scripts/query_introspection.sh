#!/usr/bin/env bash
set -euo pipefail

# Query actor introspection narratives.
#
# Usage:
#   ./scripts/query_introspection.sh                           # population summary
#   ./scripts/query_introspection.sh --actor-id <uuid>         # actor's narrative history
#   ./scripts/query_introspection.sh --sample 5                # random sample of narratives
#   ./scripts/query_introspection.sh --population "1000 personas"

POPULATION="${POPULATION:-1000 personas}"

case "${1:-}" in
  --actor-id)
    mix sim.introspect --actor-id "${2:?Missing actor-id}"
    ;;
  --population)
    mix sim.introspect --population "${2:?Missing population name}"
    ;;
  --sample)
    N="${2:-5}"
    echo "=== Random ${N} Actor Narratives ==="
    sqlite3 population_simulator_dev.db "
      SELECT
        a.stratum || ' | ' || a.zone || ' | ' || a.employment_type as perfil,
        s.narrative,
        s.self_observations
      FROM actor_summaries s
      JOIN actors a ON s.actor_id = a.id
      ORDER BY RANDOM()
      LIMIT ${N};
    " | while IFS='|' read -r perfil narrative observations; do
      echo ""
      echo "--- ${perfil} ---"
      echo "${narrative}"
      echo "Observaciones: ${observations}"
    done
    ;;
  *)
    mix sim.introspect --population "${POPULATION}"
    ;;
esac
