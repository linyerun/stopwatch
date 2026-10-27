#!/usr/bin/env bash
# 双击启动：装了就用 /Applications 里的版本，没装就现场构建再启动。
set -euo pipefail
cd "$(dirname "$0")"
if [[ -d "/Applications/念佛计时.app" ]]; then
  open "/Applications/念佛计时.app"
else
  ./build.sh
fi
