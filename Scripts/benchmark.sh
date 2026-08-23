#!/usr/bin/env bash
set -euo pipefail

PID="$(pgrep -x Dockyard || true)"
if [[ -z "$PID" ]]; then
  echo "Dockyard is not running. Launch it first." >&2
  exit 1
fi

DURATION="${DURATION:-60}"

echo "==> Process"
ps -o pid=,rss=,vsz=,pcpu=,etime= -p "$PID"

echo
echo "==> Resident memory"
echo "$(( $(ps -o rss= -p "$PID" | tr -d ' ') / 1024 )) MB"

echo
echo "==> Network sockets (expected: none)"
if lsof -nP -a -p "$PID" -i 2>/dev/null | tail -n +2 | grep -q .; then
  echo "FAIL: open network sockets detected"
  lsof -nP -a -p "$PID" -i
else
  echo "PASS: no open network sockets"
fi

echo
echo "==> Idle CPU and wakeups over ${DURATION}s (requires sudo)"
sudo powermetrics --samplers tasks -i 1000 -n "$DURATION" 2>/dev/null \
  | awk '/^Name/ {header=$0} /Dockyard/ {print}' \
  | tail -n 10
