#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DURATION="${DURATION:-60}"
LABEL="${LABEL:-idle}"

PID="$(pgrep -x Dockyard || true)"
if [[ -z "$PID" ]]; then
  echo "Dockyard is not running. Launch it first." >&2
  exit 1
fi

BINARY="$(ps -o comm= -p "$PID")"

echo "==> Build under test"
echo "$BINARY"
ps -o etime= -p "$PID" | awk '{ print "uptime " $1 }'
if otool -l "$BINARY" 2>/dev/null | grep -q "__swift5_reflstr"; then
  echo "note: swift reflection metadata present, which a release build also keeps"
fi

echo
echo "==> Network"
if lsof -nP -a -p "$PID" -i 2>/dev/null | tail -n +2 | grep -q .; then
  echo "FAIL: open network sockets"
  lsof -nP -a -p "$PID" -i
else
  echo "PASS: no open network sockets"
fi

SYMBOLS="$(nm -u "$BINARY" 2>/dev/null \
  | grep -icE 'URLSession|CFNetwork|NWConnection|CFSocket|getaddrinfo|SCNetworkReachability' || true)"
if [[ "$SYMBOLS" == "0" ]]; then
  echo "PASS: no networking symbols linked into the binary"
else
  echo "FAIL: $SYMBOLS networking symbols linked into the binary"
fi

echo
swift "$ROOT/Scripts/measure.swift" "$DURATION" "$LABEL"

echo
echo "==> Frame pacing during magnification"
echo "Scripts/frame-trace.sh   (takes over the pointer for 30 s)"
echo "==> Preference and launch latency"
echo "Scripts/latency.swift    (writes com.apple.dock tilesize, then restores it)"
