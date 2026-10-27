#!/usr/bin/env bash
# Builds 念佛计时.app with the Swift toolchain from Command Line Tools — no Xcode
# project needed. Runs the self-test against a throwaway data directory.
#
#   ./build.sh          build the app, run the self-test, then launch it
#   ./build.sh shots    additionally render UI snapshots into build/shots
#   ./build.sh install  copy the app into /Applications (launch from Launchpad)
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
  Sources/Stopwatch/MainWindow.swift
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

if [[ "${1:-}" == "install" ]]; then
  echo "==> installing to /Applications"
  rm -rf "/Applications/念佛计时.app"
  cp -R "$APP_DIR" /Applications/
  APP_DIR="/Applications/念佛计时.app"
fi

echo
echo "built: $APP_DIR"
if [[ "${NO_RUN:-}" != "1" ]]; then
  open "$APP_DIR"
  echo "已启动：菜单栏会显示「佛 …」，同时弹出计时窗口。"
fi
