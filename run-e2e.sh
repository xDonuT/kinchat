#!/usr/bin/env bash
#
# End-to-end verification in one shot:
#   1. start the Firebase Auth + Firestore emulators
#   2. boot an Android emulator
#   3. run the real app on it and drive a two-user chat flow
#
# Everything lives in one process tree so nothing dies between steps.
#
set -uo pipefail

ROOT=/home/donut
export JAVA_HOME=$ROOT/.toolchain/jdk-21.0.12.1+1   # also satisfies Gradle 9
export ANDROID_HOME=$ROOT/.toolchain/android-sdk
export ANDROID_SDK_ROOT=$ANDROID_HOME
export TMPDIR=$ROOT/.tmp
export PATH="$JAVA_HOME/bin:$ROOT/.toolchain/node/bin:$ROOT/.toolchain/flutter/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

FB=$ROOT/.toolchain/fbtools/node_modules/.bin/firebase
SRC=$ROOT/kinchat-src
APP=$ROOT/kinchat
EMULATOR_ID=""
LOG=$TMPDIR/e2e.log
: > "$LOG"

note() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nFAILED: %s\n' "$*" >&2; printf '\n--- last of firebase log ---\n'; tail -15 "$TMPDIR/emu.log" 2>/dev/null; printf '\n--- last of flutter log ---\n'; tail -30 "$TMPDIR/itest.log" 2>/dev/null; exit 1; }

cleanup() {
  [ -n "$EMULATOR_ID" ] && adb -s "$EMULATOR_ID" emu kill 2>/dev/null
  pkill -f "firebase emulators:start" 2>/dev/null
  pkill -f "qemu-system-x86_64" 2>/dev/null
}
trap cleanup EXIT INT TERM

# --- 1. Firebase emulators --------------------------------------------------
note "starting Firebase Auth + Firestore emulators"
cd "$SRC" || fail "cannot cd to $SRC"
setsid "$FB" emulators:start --only auth,firestore --project demo-kinchat \
  -c firebase.dev.json > "$TMPDIR/emu.log" 2>&1 < /dev/null &
HUB=$!
# The hub (4400) answers before Firestore (8080) finishes booting, so wait
# for the services the app actually talks to.
up() { curl -sS -o /dev/null --max-time 2 "http://127.0.0.1:$1/$2" 2>/dev/null; }
for _ in $(seq 1 45); do
  if up 4400 emulators && up 8080 '' && up 9099 emulator/v1/projects/demo-kinchat; then
    break
  fi
  sleep 2
done
if ! (up 4400 emulators && up 8080 '' && up 9099 emulator/v1/projects/demo-kinchat); then
  fail "Firebase emulators never became ready"
fi
note "firebase emulators ready (UI at http://localhost:4000)"

# --- 2. Android emulator ----------------------------------------------------
note "booting Android emulator"
EMULATOR_ID=$(adb devices | awk '/^emulator-/{print $1; exit}')
if [ -z "$EMULATOR_ID" ]; then
  setsid emulator -avd kinchat -no-window -no-audio -no-boot-anim \
    -no-snapshot -gpu swiftshader_indirect -accel on \
    > "$TMPDIR/avd.log" 2>&1 < /dev/null &
  AVD=$!
  for i in $(seq 1 50); do
    sleep 5
    EMULATOR_ID=$(adb devices | awk '/^emulator-.*device$/{print $1; exit}')
    [ -n "$EMULATOR_ID" ] && [ "$(adb -s "$EMULATOR_ID" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break
  done
fi
[ -n "$EMULATOR_ID" ] || fail "Android emulator did not appear in adb devices"
note "android emulator ready: $EMULATOR_ID"

# --- 3. run the end-to-end test --------------------------------------------
# Snapshots the screen on a timer while the test drives the app; the last
# frame lands on the finished conversation.
SHOTDIR=$TMPDIR/shots
rm -rf "$SHOTDIR"
mkdir -p "$SHOTDIR"
touch "$TMPDIR/screenshot.loop"
(
  i=0
  while [ -f "$TMPDIR/screenshot.loop" ]; do
    i=$((i + 1))
    adb -s "$EMULATOR_ID" exec-out screencap -p \
      > "$SHOTDIR/$(printf '%03d' "$i").png" 2>/dev/null || true
    sleep 4
  done
) &
SHOTPID=$!

note "running integration test on $EMULATOR_ID"
cd "$APP" || fail "cannot cd to $APP"
timeout 1200 flutter test integration_test/app_test.dart -d "$EMULATOR_ID" \
  --dart-define=USE_EMULATOR=true \
  --dart-define=EMULATOR_HOST=10.0.2.2 \
  > "$TMPDIR/itest.log" 2>&1
CODE=$?

rm -f "$TMPDIR/screenshot.loop"
kill "$SHOTPID" 2>/dev/null || true
wait "$SHOTPID" 2>/dev/null || true
# Keep only usable frames and publish the final one.
find "$SHOTDIR" -name '*.png' -size -1000c -delete 2>/dev/null
FINAL=$(ls -1 "$SHOTDIR"/*.png 2>/dev/null | tail -1)
[ -n "$FINAL" ] && cp "$FINAL" "$TMPDIR/kinchat-final.png" && \
  note "screenshot saved: $TMPDIR/kinchat-final.png"

echo
grep -vE "^\s*$|WARNING|warning:|^\s+/\s*$" "$TMPDIR/itest.log" | tail -40
echo
[ $CODE -eq 0 ] && note "E2E TEST PASSED" || fail "integration test exited with code $CODE"
exit 0