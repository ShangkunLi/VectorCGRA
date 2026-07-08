#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLOW_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${FLOW_DIR}"

DESIGN="${DESIGN:-amoeba_grid}"
LAYOUT_DIR="${LAYOUT_DIR:-reports/layout}"
BASENAME="${BASENAME:-${DESIGN}_post_route_layout}"
DPI="${DPI:-900}"
PNG_OUT="${LAYOUT_DIR}/${BASENAME}.png"

mkdir -p "${LAYOUT_DIR}"

if ! command -v convert >/dev/null 2>&1; then
  echo "ImageMagick convert not found; skipping PNG post-processing." >&2
  exit 0
fi

convert_pdf() {
  local input_file="$1"
  convert -density "${DPI}" "${input_file}" \
    -trim +repage -background white -alpha remove -alpha off \
    -quality 100 "${PNG_OUT}"
}

convert_gif() {
  local input_file="$1"
  convert "${input_file}" \
    -trim +repage -filter Lanczos -resize 3600x3600 \
    -quality 100 "${PNG_OUT}"
}

if [ -f "${LAYOUT_DIR}/${BASENAME}.pdf" ]; then
  if convert_pdf "${LAYOUT_DIR}/${BASENAME}.pdf"; then
    echo "Wrote high-resolution PNG: ${PNG_OUT}"
    exit 0
  fi
fi

if [ -f "${LAYOUT_DIR}/${BASENAME}.ps" ]; then
  if convert_pdf "${LAYOUT_DIR}/${BASENAME}.ps"; then
    echo "Wrote high-resolution PNG: ${PNG_OUT}"
    exit 0
  fi
fi

if [ -f "${LAYOUT_DIR}/${BASENAME}.gif" ]; then
  if convert_gif "${LAYOUT_DIR}/${BASENAME}.gif"; then
    echo "Wrote PNG from GIF fallback: ${PNG_OUT}"
    exit 0
  fi
fi

echo "No layout image found to post-process under ${LAYOUT_DIR}." >&2
exit 0
