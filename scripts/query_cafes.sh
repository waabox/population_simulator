#!/usr/bin/env bash
set -euo pipefail

# Query café conversations.
#
# Usage:
#   ./scripts/query_cafes.sh                           # latest measure, all zones
#   ./scripts/query_cafes.sh --zone suburbs_outer      # filter by zone
#   ./scripts/query_cafes.sh --actor-id <uuid>         # actor's café history
#   ./scripts/query_cafes.sh --measure-id <uuid>       # specific measure
#   ./scripts/query_cafes.sh --stats                   # summary stats

if [ $# -eq 0 ] || [ "${1:-}" = "--stats" ]; then
  echo "=== Café Stats ==="
  sqlite3 -column -header population_simulator_dev.db "
    SELECT
      cs.group_key as mesa,
      COUNT(DISTINCT json_each.value) as participantes,
      cs.conversation_summary as resumen
    FROM cafe_sessions cs,
      json_each(cs.participant_ids)
    WHERE cs.measure_id = (SELECT id FROM measures ORDER BY inserted_at DESC LIMIT 1)
    GROUP BY cs.id
    ORDER BY cs.group_key
    LIMIT 20;
  "
  echo ""
  sqlite3 population_simulator_dev.db "
    SELECT 'Total mesas: ' || COUNT(*) FROM cafe_sessions
    WHERE measure_id = (SELECT id FROM measures ORDER BY inserted_at DESC LIMIT 1);
    SELECT 'Total effects: ' || COUNT(*) FROM cafe_effects
    WHERE cafe_session_id IN (
      SELECT id FROM cafe_sessions
      WHERE measure_id = (SELECT id FROM measures ORDER BY inserted_at DESC LIMIT 1)
    );
  "
  exit 0
fi

case "${1:-}" in
  --actor-id)
    mix sim.cafe --actor-id "${2:?Missing actor-id}"
    ;;
  --zone)
    MEASURE_ID=$(sqlite3 population_simulator_dev.db "SELECT id FROM measures ORDER BY inserted_at DESC LIMIT 1")
    mix sim.cafe --measure-id "${MEASURE_ID}" --zone "${2:?Missing zone}"
    ;;
  --measure-id)
    mix sim.cafe --measure-id "${2:?Missing measure-id}"
    ;;
  *)
    echo "Usage:"
    echo "  ./scripts/query_cafes.sh --stats"
    echo "  ./scripts/query_cafes.sh --zone suburbs_outer"
    echo "  ./scripts/query_cafes.sh --actor-id <uuid>"
    echo "  ./scripts/query_cafes.sh --measure-id <uuid>"
    ;;
esac
