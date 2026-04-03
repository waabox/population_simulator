#!/usr/bin/env bash
set -euo pipefail

# Clean simulation data while keeping actors and their initial state.
#
# Usage:
#   ./scripts/clean_simulation.sh              # clean everything except actors
#   ./scripts/clean_simulation.sh --full       # also re-seed actors (requires EPH data)

DB="population_simulator_dev.db"

echo "=== Clean Simulation Data ==="

if [ "${1:-}" = "--full" ]; then
  echo "Full clean: removing all data including actors..."
  sqlite3 "${DB}" "
    DELETE FROM cafe_effects;
    DELETE FROM cafe_sessions;
    DELETE FROM actor_summaries;
    DELETE FROM actor_beliefs;
    DELETE FROM actor_moods;
    DELETE FROM decisions;
    DELETE FROM measures;
    DELETE FROM actor_populations;
    DELETE FROM actors;
    DELETE FROM populations;
  "
  echo "Done. Re-seed with: mix sim.seed --n 1000 --population \"1000 personas\""
else
  echo "Cleaning simulation data (keeping actors + initial moods/beliefs)..."
  sqlite3 "${DB}" "
    DELETE FROM cafe_effects;
    DELETE FROM cafe_sessions;
    DELETE FROM actor_summaries;
    DELETE FROM actor_beliefs WHERE decision_id IS NOT NULL;
    DELETE FROM actor_moods WHERE decision_id IS NOT NULL;
    DELETE FROM actor_moods WHERE decision_id IS NULL AND measure_id IS NOT NULL;
    DELETE FROM decisions;
    DELETE FROM measures;
  "
  echo "Done."
fi

echo ""
sqlite3 "${DB}" "
  SELECT 'Actors: ' || COUNT(*) FROM actors;
  SELECT 'Initial moods: ' || COUNT(*) FROM actor_moods;
  SELECT 'Initial beliefs: ' || COUNT(*) FROM actor_beliefs;
  SELECT 'Measures: ' || COUNT(*) FROM measures;
  SELECT 'Decisions: ' || COUNT(*) FROM decisions;
  SELECT 'Café sessions: ' || COUNT(*) FROM cafe_sessions;
  SELECT 'Introspections: ' || COUNT(*) FROM actor_summaries;
"
