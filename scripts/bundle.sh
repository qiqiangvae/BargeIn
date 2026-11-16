#!/usr/bin/env bash
# 组装 Barge In.app：本机只有 Command Line Tools，不走 xcodeproj。
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP_NAME="Barge In"
BIN_NAME="BargeIn"
CONFIG="${1:-release}"
APP="${APP_NAME}.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "${APP:?}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_DIR}/${BIN_NAME}" "${APP}/Contents/MacOS/${BIN_NAME}"
cp Info.plist "${APP}/Contents/Info.plist"

# 图标源在代码里（BrandMark），打包时生成，仓库不存二进制图标。
ICONS="$(mktemp -d)"
"${APP}/Contents/MacOS/${BIN_NAME}" --export-icon "${ICONS}"
cp "${ICONS}/AppIcon.icns" "${APP}/Contents/Resources/AppIcon.icns"
rm -rf "${ICONS:?}"

# ad-hoc 签名：足够本机运行，正式分发需要 Developer ID + 公证。
codesign --force --sign - "${APP}"

echo "built $(pwd)/${APP}"
