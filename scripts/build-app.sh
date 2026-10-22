#!/bin/zsh
# Koebumi.app を作って署名する。
#   ./scripts/build-app.sh                   → build/Koebumi.app
#   ./scripts/build-app.sh --install         → ~/Applications/Koebumi.app にコピーして起動
#   ./scripts/build-app.sh --version 0.2.0   → 表示するバージョンを指定する（配布用は scripts/release.sh から呼ぶ）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Koebumi.app"
BUNDLE_ID="io.github.koebumi.Koebumi"
VERSION="0.1.0"
INSTALL=0
while (( $# )); do
    case "$1" in
        --install) INSTALL=1 ;;
        --version) VERSION="$2"; shift ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done
# ビルド番号はコミット数にする。Sparkle はこの番号で新しい版かどうかを決めるので、増え続ける必要がある
BUILD="$(git -C "$ROOT" rev-list --count HEAD)"

# 自動アップデート。appcast.xml は最新のリリースに置くので、この URL はいつも最新の版を指す
FEED_URL="https://github.com/koebumi/koebumi/releases/latest/download/appcast.xml"
# 秘密鍵はキーチェーンにある（generate_keys --account koebumi で作った）。公開鍵はここに書く
SPARKLE_PUBLIC_KEY="OcnN2ZJSqAxZK4mp7OgIkyB8+jGDSvxsL6AmTR8iZzM="

cd "$ROOT"
swift build -c release --product Koebumi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
BIN="$(swift build -c release --show-bin-path)"
cp "$BIN/Koebumi" "$APP/Contents/MacOS/Koebumi"
# 依存パッケージのリソース。MLX の Metal シェーダー（mlx-swift_Cmlx.bundle の default.metallib）もここに入る。
for bundle in "$BIN"/*.bundle; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done
# Sparkle はフレームワークとして読み込む。シンボリックリンクを保つため ditto で写す
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Koebumi"

# 使っているパッケージのライセンス。MIT と Apache 2.0 は、配るものにライセンス文と著作権表示（NOTICE があればそれも）を入れる
setopt extended_glob
{
    print "Koebumi includes the following open source software."
    for file in "$ROOT"/.build/checkouts/*/(#i)(license|licence|copying|notice)*(N.); do
        print "\n==== ${file:h:t} (${file:t}) ====\n"
        cat "$file"
    done
} > "$APP/Contents/Resources/ThirdPartyLicenses.txt"

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
    <key>CFBundleName</key><string>Koebumi</string>
    <key>CFBundleDisplayName</key><string>Koebumi</string>
    <key>CFBundleExecutable</key><string>Koebumi</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>話した声を文字に起こすためにマイクを使います。</string>
    <key>NSSpeechRecognitionUsageDescription</key><string>話した声をこの Mac の上で文字に起こすために使います。</string>
    <key>NSHumanReadableCopyright</key><string>Koebumi</string>
    <key>SUFeedURL</key><string>$FEED_URL</string>
    <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

# 署名。Apple Development の証明書があれば使う（アクセシビリティ許可がビルドし直しても外れない）。
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="-"
    echo "Ad-hoc signed (re-grant Accessibility after each rebuild)"
fi
# 中のものから順に署名する。Sparkle は配布物が仮の署名なので、アプリと同じ証明書で署名し直す
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for code in "$SPARKLE/XPCServices/Installer.xpc" "$SPARKLE/XPCServices/Downloader.xpc" \
            "$SPARKLE/Autoupdate" "$SPARKLE/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --sign "$IDENTITY" --timestamp=none --preserve-metadata=entitlements "$code"
done
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
if [[ "$IDENTITY" != "-" ]]; then echo "Signed with: $IDENTITY"; fi

echo "Built: $APP ($VERSION, build $BUILD)"

if (( INSTALL )); then
    DEST="$HOME/Applications/Koebumi.app"
    mkdir -p "$HOME/Applications"
    pkill -x Koebumi 2>/dev/null || true
    # 終わりきる前に open すると、起動に失敗する（エラー -600）。10 秒待っても残っていれば強制終了する
    for _ in {1..100}; do
        pgrep -x Koebumi >/dev/null || break
        sleep 0.1
    done
    if pgrep -x Koebumi >/dev/null; then
        pkill -9 -x Koebumi 2>/dev/null || true
        sleep 0.5
    fi
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "Installed: $DEST"
fi
