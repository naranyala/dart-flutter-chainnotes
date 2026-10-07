#!/usr/bin/env bash
# Smoke-run the real Linux desktop binary on a display.
#
# Builds the debug bundle, then launches it with isolated XDG directories so
# a smoke run can never read or rewrite a real workspace. The app is expected
# to stay up, so `timeout` killing it after the window is the success path.
#
# Usage:
#   tool/smoke.sh [--timeout 20] [--build]
#
# Remediation when there is no display is a precise message, not a hang.
set -euo pipefail

TIMEOUT_S=20
DO_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --timeout) shift ;;
    --timeout=*) TIMEOUT_S="${arg#--timeout=}" ;;
    --build) DO_BUILD=1 ;;
    [0-9]*) TIMEOUT_S="$arg" ;;
    *) echo "Unknown arg: $arg (expected --build or --timeout=N)" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="$ROOT/build/linux/x64/debug/bundle/chainnotes"

if [ "$DO_BUILD" = "1" ]; then
  (cd "$ROOT" && flutter build linux --debug)
fi

if [ ! -x "$BINARY" ]; then
  echo "Missing binary: $BINARY" >&2
  echo "Run: flutter build linux --debug  (or tool/smoke.sh --build)" >&2
  exit 1
fi

SCRATCH="$(mktemp -d -t chainnotes-smoke-XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT
export XDG_DATA_HOME="$SCRATCH/data"
export XDG_CACHE_HOME="$SCRATCH/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CACHE_HOME"
LOG="$SCRATCH/smoke.log"

RUN=()
if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
  RUN=(timeout "$TIMEOUT_S" "$BINARY")
elif command -v xvfb-run >/dev/null 2>&1; then
  RUN=(xvfb-run -a timeout "$TIMEOUT_S" "$BINARY")
else
  echo "No display found (DISPLAY and WAYLAND_DISPLAY are unset) and xvfb-run is not installed." >&2
  echo "Remediation: run on a machine with a display, or install Xvfb (e.g. 'sudo apt install xvfb') then re-run tool/smoke.sh." >&2
  exit 3
fi

set +e
"${RUN[@]}" >"$LOG" 2>&1
CODE=$?
set -e

# 124 = timeout killed it => the app stayed up for the whole window. 0 = it
# exited cleanly on its own. Anything else is a launch/runtime failure.
if [ "$CODE" -ne 124 ] && [ "$CODE" -ne 0 ]; then
  echo "Smoke run failed with exit code $CODE. Last 40 log lines:" >&2
  tail -40 "$LOG" >&2 || true
  exit "$CODE"
fi

if grep -Ei "flutter (error|exception)|unhandled|crash| (!|✗|failed)" "$LOG" >/dev/null 2>&1; then
  echo "Smoke run exited $CODE but the log contains an error marker:" >&2
  grep -Ei "flutter (error|exception)|unhandled|crash| (!|✗|failed)" "$LOG" >&2 | head -20
  exit 1
fi

echo "Smoke OK (exit=$CODE, timeout=${TIMEOUT_S}s, log=$LOG, scratch kept only on failure)."
