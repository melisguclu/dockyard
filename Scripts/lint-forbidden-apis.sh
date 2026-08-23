#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGETS=(
  "$ROOT/Packages/DockCore/Sources"
  "$ROOT/Packages/DockKit/Sources"
  "$ROOT/Dockyard"
)

STATUS=0

check() {
  local label="$1"
  local pattern="$2"
  local hits
  hits="$(grep -rnE --include='*.swift' "$pattern" "${TARGETS[@]}" 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    echo "FORBIDDEN: $label"
    echo "$hits"
    STATUS=1
  else
    echo "ok: $label"
  fi
}

check "subprocess execution" '(^|[^A-Za-z0-9_.])Process\(|posix_spawn|NSTask|(^|[^A-Za-z0-9_.])system\('
check "AppleScript" 'NSAppleScript|OSAScript|NSUserAppleScriptTask|NSAppleEventDescriptor'
check "network access" 'URLSession|NWConnection|NWListener|import Network|CFSocket|SCNetworkReachability'
check "signals to other processes" 'killall|[^A-Za-z0-9_]kill\(|SIGKILL|SIGTERM'
check "polling timers" 'Timer\.scheduledTimer|DispatchSourceTimer|makeTimerSource|CVDisplayLink|NSTimer'
check "force try or force cast" 'try!|as!'
check "force unwrapping" '[A-Za-z0-9_\)\]][!](\.|\)|,|;|$| [^=])'
check "unchecked sendable" '@unchecked Sendable'
check "private api loading" 'dlsym|dlopen|_objc_msgSend|NSClassFromString'

exit "$STATUS"
