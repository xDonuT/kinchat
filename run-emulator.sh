#!/usr/bin/env bash
#
# Starts the local Firebase emulators and runs KinChat against them.
# Nothing here touches your real Firebase project.
#
#   ./run-emulator.sh
#
# Overrides:
#   EMULATOR_HOST=192.168.1.20 ./run-emulator.sh
#
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
cd "$SRC"

RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; OFF=$'\033[0m'

die() { echo "${RED}error:${OFF} $*" >&2; exit 1; }
note() { echo "${YEL}==>${OFF} $*"; }
ok()   { echo "${GRN}==>${OFF} $*"; }

command -v flutter >/dev/null 2>&1 || die \
  "flutter not found on PATH. See https://docs.flutter.dev/get-started/install"
command -v firebase >/dev/null 2>&1 || die \
  "firebase CLI not found. Install it with:  npm install -g firebase-tools"

# The Firestore emulator needs Java 21 or newer; newer firebase-tools versions
# refuse to start otherwise.
if ! java -version >/dev/null 2>&1; then
  die "java not found. The Firestore emulator needs JDK 21+ (Linux: sudo apt install openjdk-21-jdk)"
fi
JAVA_MAJOR=$(java -version 2>&1 | head -1 | sed -E 's/.*version "([0-9]+).*/\1/')
if [ "${JAVA_MAJOR:-0}" -lt 21 ]; then
  die "java $JAVA_MAJOR found, but the Firestore emulator needs 21 or newer.
     macOS:  brew install openjdk@21
     Linux:  sudo apt install openjdk-21-jdk
     Or point JAVA_HOME at a JDK 21 before running this script."
fi

# Work out how the phone should reach this computer.
if [ -n "${EMULATOR_HOST:-}" ]; then
  HOST="$EMULATOR_HOST"
  HOST_SOURCE="your EMULATOR_HOST setting"
elif flutter devices 2>/dev/null | grep -qE 'emulator-[0-9]+'; then
  HOST="10.0.2.2"
  HOST_SOURCE="an Android emulator is running (10.0.2.2 is its alias for this PC)"
else
  HOST=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
  [ -n "$HOST" ] || HOST=$(hostname -I 2>/dev/null | awk '{print $1}')
  [ -n "$HOST" ] || HOST="10.0.2.2"
  HOST_SOURCE="this PC's network address"
fi

echo
ok "KinChat test mode"
echo "    emulator host: $HOST   (from $HOST_SOURCE)"
echo "    emulator UI:   http://localhost:4000"
echo "    a yellow TEST MODE stripe will appear in the app."
echo

# --- start the emulators ---------------------------------------------------
note "starting emulators..."
setsid firebase emulators:start \
  --only auth,firestore \
  --project demo-kinchat \
  -c firebase.dev.json \
  > /tmp/kinchat-emulator.log 2>&1 < /dev/null &
EMU_PID=$!

cleanup() {
  echo
  note "stopping emulators..."
  kill "$EMU_PID" 2>/dev/null || true
  pkill -f "firebase emulators:start" 2>/dev/null || true
  wait "$EMU_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Wait for the hub to answer rather than guessing with sleep.
READY=0
for _ in $(seq 1 60); do
  if curl -sS -o /dev/null "http://127.0.0.1:4400/emulators" 2>/dev/null; then
    READY=1
    break
  fi
  sleep 2
done

if [ "$READY" -ne 1 ]; then
  note "emulators did not come up. Last lines of the log:"
  tail -25 /tmp/kinchat-emulator.log >&2
  die "emulator startup failed"
fi

ok "emulators ready"

# --- run the app against them ----------------------------------------------
note "launching app..."
echo
flutter run \
  --dart-define=USE_EMULATOR=true \
  --dart-define=EMULATOR_HOST="$HOST"