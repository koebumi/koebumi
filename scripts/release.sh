#!/bin/zsh
# 配布する版を作る。build/release/ に zip・appcast.xml・リリースノートを置き、GitHub Releases に上げるコマンドを表示する。
#   ./scripts/release.sh 0.1.0
# zip は Sparkle の鍵（キーチェーンの koebumi。generate_keys --account koebumi で作った）で署名する。
# 初めて署名するときは、sign_update がキーチェーンを使ってよいかの確認が出る（「常に許可」を選ぶ）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?usage: ./scripts/release.sh <version>（例: 0.1.0）}"
TAG="v$VERSION"
REPO="koebumi/koebumi"
OUT="$ROOT/build/release"
APP="$ROOT/build/Koebumi.app"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"

cd "$ROOT"
# 配った版とコミットを対応させるため、変更が残っていたら作らない
if [[ -n "$(git status --porcelain)" ]]; then
    echo "コミットしていない変更があります。コミットしてからやり直してください。" >&2
    exit 1
fi

./scripts/build-app.sh --version "$VERSION"
codesign --verify --deep --strict "$APP"
BUILD="$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")"

rm -rf "$OUT"
mkdir -p "$OUT"
ZIP_NAME="Koebumi-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/$ZIP_NAME"
# sparkle:edSignature="…" length="…" の形で返る
SIGNATURE="$("$SPARKLE_BIN/sign_update" --account koebumi "$OUT/$ZIP_NAME")"

# 変更点。前の版のタグからの main のコミット（マージは説明つきの 1 行になる）。タグがなければ最初の版
PREVIOUS="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
if [[ -n "$PREVIOUS" ]]; then
    CHANGES="$(git log --first-parent --format='%s' "$PREVIOUS..HEAD")"
else
    CHANGES="最初の試用版です。"
fi

# Sparkle のアップデート画面に出す変更点（HTML）
CHANGES_HTML="$(print -r -- "$CHANGES" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's|.*|<li>&</li>|')"
cat > "$OUT/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Koebumi</title>
    <item>
      <title>Koebumi $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>
$CHANGES_HTML
</ul>]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/$TAG/$ZIP_NAME" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML

# GitHub Releases の本文。試してもらう人向けの入れ方も書く
cat > "$OUT/notes.md" <<NOTES
## 変更点

$(print -r -- "$CHANGES" | sed 's/^/- /')

## 入れ方

必要な環境: macOS 26 以降、Apple シリコンの Mac

1. 下の $ZIP_NAME をダウンロードして開く
2. 出てきた Koebumi.app を「アプリケーション」フォルダに入れる
3. Koebumi.app を開く。「開けませんでした」と出たら「完了」を押す
4. システム設定 > プライバシーとセキュリティ を開き、下のほうにある「Koebumi」の「このまま開く」を押す
5. セットアップ画面に沿って、マイクとアクセシビリティを許可する

3 と 4 は最初の 1 回だけです。次の版からは、アプリが自動で知らせます。
NOTES

echo
echo "作ったもの: $OUT（$VERSION、ビルド $BUILD）"
echo "公開するには、main を push してから次を実行します:"
echo "  gh release create $TAG '$OUT/$ZIP_NAME' '$OUT/appcast.xml' --repo $REPO --target \$(git rev-parse HEAD) --title 'Koebumi $VERSION' --notes-file '$OUT/notes.md'"
