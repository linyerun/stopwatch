#!/usr/bin/env bash
# Builds 念佛计时.app with the Swift toolchain from Command Line Tools — no Xcode
# project needed. Runs the self-test against a throwaway data directory.
#
#   ./build.sh          build the app and run the self-test
#   ./build.sh shots    additionally render UI snapshots into build/shots
set -euo pipefail
cd "$(dirname "$0")"

APP_DIR="build/念佛计时.app"
EXE="Stopwatch"
TARGET="arm64-apple-macosx13.0"
OPTS=(-O -target "$TARGET" -framework SwiftUI -framework AppKit)

# Everything except the @main entry point, so the test and snapshot tools can own main.
UI_SOURCES=(
  Sources/Stopwatch/TimerModel.swift
  Sources/Stopwatch/SampleData.swift
  Sources/Stopwatch/Exporter.swift
  Sources/Stopwatch/MenuBarUI.swift
  Sources/Stopwatch/HistoryView.swift
  Sources/Stopwatch/HistoryWindow.swift
)

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "==> compiling app"
swiftc "${OPTS[@]}" -parse-as-library "${UI_SOURCES[@]}" Sources/Stopwatch/AppMain.swift \
  -o "$APP_DIR/Contents/MacOS/$EXE"

echo "==> bundling"
cp Info.plist "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
codesign --force --sign - "$APP_DIR" >/dev/null

echo "==> compiling self-test"
swiftc "${OPTS[@]}" \
  Sources/Stopwatch/TimerModel.swift \
  Sources/Stopwatch/Exporter.swift \
  Sources/Stopwatch/SelfTest.swift \
  Sources/StopwatchTests/main.swift \
  -o build/stopwatch-selftest

echo "==> running self-test"
./build/stopwatch-selftest

if [[ "${1:-}" == "shots" ]]; then
  echo "==> rendering UI snapshots"
  swiftc "${OPTS[@]}" "${UI_SOURCES[@]}" Sources/SnapshotTool/main.swift \
    -o build/stopwatch-shots
  rm -rf build/shots build/shots-data
  mkdir -p build/shots
  NIANFO_DATA_DIR="$PWD/build/shots-data" ./build/stopwatch-shots "$PWD/build/shots"
fi

echo
echo "built: $APP_DIR"
echo "run:   open '$APP_DIR'   (timer appears in the menu bar)"
