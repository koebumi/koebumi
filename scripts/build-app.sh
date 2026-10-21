#!/bin/zsh
# Speak.app を作って署名する。
#   ./scripts/build-app.sh            → build/Speak.app
#   ./scripts/build-app.sh --install  → ~/Applications/Speak.app にコピーして起動
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Speak.app"
BUNDLE_ID="local.speak.app"
VERSION="1.0.0"

cd "$ROOT"
swift build -c release --product Speak

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN="$(swift build -c release --show-bin-path)"
cp "$BIN/Speak" "$APP/Contents/MacOS/Speak"
# 依存パッケージのリソース。MLX の Metal シェーダー（mlx-swift_Cmlx.bundle の default.metallib）もここに入る。
for bundle in "$BIN"/*.bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done

# アイコン。Resources/AppIcon.icon（Icon Composer 形式）から Assets.car と AppIcon.icns を作る。
# ダーク・クリア・ティントの見た目は Assets.car に入る。actool は Xcode が必要。
xcrun actool "$ROOT/Resources/AppIcon.icon" --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon \
    --output-partial-info-plist "$ROOT/build/AppIcon-partial.plist" >/dev/null

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>Speak</string>
    <key>CFBundleDisplayName</key><string>Speak</string>
    <key>CFBundleExecutable</key><string>Speak</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>話した声を文字に起こすためにマイクを使います。</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>話した声をこの Mac の上で文字に起こすために使います。</string>
    <key>NSHumanReadableCopyright</key><string>Speak</string>
</dict>
</plist>
PLIST

# 署名。Apple Development の証明書があれば使う（アクセシビリティ許可がビルドし直しても外れない）。
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "Ad-hoc signed (re-grant Accessibility after each rebuild)"
fi

echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST="$HOME/Applications/Speak.app"
    mkdir -p "$HOME/Applications"
    pkill -x Speak 2>/dev/null || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "Installed: $DEST"
fi
