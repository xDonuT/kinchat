#!/usr/bin/env bash
#
# Starts the Firebase emulators, runs the security rules tests, then stops
# everything. Exits non-zero if any rule check fails.
#
#   ./run-rules-tests.sh
#
set -uo pipefail

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT" || exit 1

export JAVA_HOME=${JAVA_HOME:-/home/donut/.toolchain/jdk-21.0.12.1+1}
export PATH="$JAVA_HOME/bin:/home/donut/.toolchain/node/bin:$PATH"
export TMPDIR=${TMPDIR:-/home/donut/.tmp}
export NODE_PATH=${NODE_PATH:-/home/donut/.toolchain/fbtools/node_modules}

FB=${FB:-"$HOME/.toolchain/fbtools/node_modules/.bin/firebase"}
LOG="$TMPDIR/rules-emulator.log"
mkdir -p "$TMPDIR"

if ! command -v node >/dev/null 2>&1; then
  echo "error: node not on PATH" >&2
  exit 1
fi
if ! node -e "require.resolve('@firebase/rules-unit-testing')" >/dev/null 2>&1; then
  echo "error: @firebase/rules-unit-testing not installed." >&2
  echo "       npm i -D @firebase/rules-unit-testing firebase" >&2
  exit 1
fi

# pkill -f would match this script's own command line and kill it, so match
# the emulator's Java process by its well-known class name instead.
EMULATOR_PID=""
cleanup() {
  if [ -n "$EMULATOR_PID" ]; then
    kill "$EMULATOR_PID" 2>/dev/null || true
    wait "$EMULATOR_PID" 2>/dev/null || true
  fi
  # Firestore runs as a Java child process; stop it if the parent is gone.
  pkill -f "cloud-firestore-emulator" 2>/dev/null || true
  pkill -f "CloudFirestoreMain" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "==> starting emulators (production firestore.rules)"
setsid "$FB" emulators:start --only auth,firestore \
  --project demo-kinchat -c firebase.json > "$LOG" 2>&1 < /dev/null &
EMULATOR_PID=$!

# The hub (4400) comes up before Firestore (8080) finishes booting, so wait
# for the actual services, not just the hub.
up() { curl -sS -o /dev/null --max-time 2 "http://127.0.0.1:$1/$2" 2>/dev/null; }
for _ in $(seq 1 45); do
  if up 4400 emulators && up 8080 '' && up 9099 emulator/v1/projects/demo-kinchat; then
    break
  fi
  sleep 2
done
if ! (up 4400 emulators && up 8080 '' && up 9099 emulator/v1/projects/demo-kinchat); then
  echo "error: emulators did not become ready. Log tail:" >&2
  tail -20 "$LOG" >&2
  exit 1
fi
echo "==> emulators ready (hub 4400, firestore 8080, auth 9099)"

echo "==> running security rules tests"
node tests/rules.test.js 2>&1
CODE=$?
exit "$CODE"