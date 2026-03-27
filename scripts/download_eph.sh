#!/usr/bin/env bash
set -euo pipefail

# Downloads and extracts EPH microdata from INDEC.
#
# Usage:
#   ./scripts/download_eph.sh              # Downloads T4 2024 (default)
#   ./scripts/download_eph.sh 4 2024       # Downloads T4 2024
#   ./scripts/download_eph.sh 3 2024       # Downloads T3 2024
#
# Source: INDEC EPH via ropensci/eph URL pattern
# URL pattern: https://www.indec.gob.ar/ftp/cuadros/menusuperior/eph/EPH_usu_{period}_Trim_{year}_txt.zip

PERIOD="${1:-4}"
YEAR="${2:-2024}"

BASE_URL="https://www.indec.gob.ar/ftp/cuadros/menusuperior/eph"
ZIP_FILE="EPH_usu_${PERIOD}_Trim_${YEAR}_txt.zip"
DOWNLOAD_URL="${BASE_URL}/${ZIP_FILE}"

DATA_DIR="priv/data/eph"
TMP_DIR=$(mktemp -d)

trap 'rm -rf "${TMP_DIR}"' EXIT

echo "=== EPH Data Downloader ==="
echo "Period: T${PERIOD} ${YEAR}"
echo "URL: ${DOWNLOAD_URL}"
echo ""

mkdir -p "${DATA_DIR}"

echo "Downloading ${ZIP_FILE}..."
if ! curl -fSL --progress-bar -o "${TMP_DIR}/${ZIP_FILE}" "${DOWNLOAD_URL}"; then
  echo ""
  echo "ERROR: Failed to download from ${DOWNLOAD_URL}"
  echo ""
  echo "Try a different trimester:"
  echo "  ./scripts/download_eph.sh 3 2024"
  echo "  ./scripts/download_eph.sh 2 2024"
  exit 1
fi

# Verify it's actually a zip
if ! file "${TMP_DIR}/${ZIP_FILE}" | grep -q "Zip archive"; then
  echo "ERROR: Downloaded file is not a valid zip archive."
  echo "INDEC may have changed their URL structure."
  file "${TMP_DIR}/${ZIP_FILE}"
  exit 1
fi

echo "Extracting..."
unzip -o "${TMP_DIR}/${ZIP_FILE}" -d "${TMP_DIR}/extracted"

echo ""
echo "Looking for individual and hogar files..."

INDIVIDUAL=$(find "${TMP_DIR}/extracted" -iname "*individual*" -type f | head -1)
HOGAR=$(find "${TMP_DIR}/extracted" -iname "*hogar*" -type f | head -1)

if [ -z "${INDIVIDUAL}" ]; then
  echo "WARNING: Could not find individual file."
  find "${TMP_DIR}/extracted" -type f
  exit 1
else
  cp "${INDIVIDUAL}" "${DATA_DIR}/individual.txt"
  echo "Individual: $(basename "${INDIVIDUAL}") -> ${DATA_DIR}/individual.txt"
fi

if [ -z "${HOGAR}" ]; then
  echo "WARNING: Could not find hogar file."
  find "${TMP_DIR}/extracted" -type f
  exit 1
else
  cp "${HOGAR}" "${DATA_DIR}/hogar.txt"
  echo "Hogar: $(basename "${HOGAR}") -> ${DATA_DIR}/hogar.txt"
fi

echo ""
echo "=== File info ==="
file "${DATA_DIR}/individual.txt"
INDIVIDUAL_LINES=$(wc -l < "${DATA_DIR}/individual.txt" | tr -d ' ')
echo "Individual: ${INDIVIDUAL_LINES} lines"

file "${DATA_DIR}/hogar.txt"
HOGAR_LINES=$(wc -l < "${DATA_DIR}/hogar.txt" | tr -d ' ')
echo "Hogar: ${HOGAR_LINES} lines"

# Count GBA records (CABA=32 + Partidos GBA=33)
GBA_COUNT=$(awk -F';' 'NR>1 && ($9=="32" || $9=="33")' "${DATA_DIR}/individual.txt" | wc -l | tr -d ' ')
echo ""
echo "GBA records (CABA + Conurbano): ${GBA_COUNT}"

echo ""
echo "Done. Files saved to ${DATA_DIR}/"
