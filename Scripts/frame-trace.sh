#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECONDS_TO_SWEEP="${DURATION:-30}"
SPEED="${SPEED:-500}"
OUT="${OUT:-$(mktemp -d)}"
TRACE="$OUT/magnification.trace"
mkdir -p "$OUT"

PID="$(pgrep -x Dockyard || true)"
if [[ -z "$PID" ]]; then
  echo "Dockyard is not running. Launch it first." >&2
  exit 1
fi

echo "==> Recording $((SECONDS_TO_SWEEP + 4)) s into $TRACE"
rm -rf "$TRACE"
xcrun xctrace record --template "Logging" --attach "$PID" \
  --output "$TRACE" --time-limit $((SECONDS_TO_SWEEP + 4))s > "$OUT/record.log" 2>&1 &
RECORDER=$!

sleep 2.5
swift "$ROOT/Scripts/sweep-cursor.swift" "$SECONDS_TO_SWEEP" "$SPEED"
wait $RECORDER

xcrun xctrace export --input "$TRACE" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost-interval"]' \
  > "$OUT/intervals.xml"

python3 "$ROOT/Scripts/frame-stats.py" "$OUT/intervals.xml"
