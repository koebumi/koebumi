#!/bin/zsh
# speech.cpp（https://github.com/nyosegawa/speech.cpp、MIT）の speech コマンドを取ってきて build/speech.cpp/ に置く。
# Haas ja v1.0 を動かすのに使う（Sources/Koebumi/Speech/SpeechCppModel.swift）。build-app.sh はこれをアプリの Contents/Helpers に入れる。
#   ./scripts/fetch-speech-cpp.sh
# 版とチェックサムはここで固定する。版を上げるときは、SHA256SUMS の値と SpeechCpp.version も合わせる。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="0.10.0"
SHA256="4f48ac4aefe65a00e2724e94749f01f7993de6190998c49bb347662f96f7af6d"
# speech は ggml を静的にリンクしている。ライセンス文を配るものに入れるため、その版の ggml（サブモジュール）のコミットも固定する
GGML_REPO="nyosegawa/ggml"
GGML_COMMIT="700c9d743ed7cc583c0f1b6507afebb6c0e88bc0"
DEST="$ROOT/build/speech.cpp"

if [[ -x "$DEST/speech" && "$(cat "$DEST/VERSION" 2>/dev/null)" == "$VERSION" ]]; then
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/speech.zip" \
    "https://github.com/nyosegawa/speech.cpp/releases/download/v$VERSION/speech-$VERSION-macos-arm64-metal.zip"
echo "$SHA256  $TMP/speech.zip" | shasum -a 256 -c - >/dev/null
# 使うのは speech コマンドだけ（ggml も中に入っている）。libspeech と speech.h は使わない
unzip -q "$TMP/speech.zip" speech -d "$TMP/out"
mkdir -p "$TMP/out/licenses"
curl -fsSL -o "$TMP/out/licenses/speech.cpp-LICENSE" "https://raw.githubusercontent.com/nyosegawa/speech.cpp/v$VERSION/LICENSE"
curl -fsSL -o "$TMP/out/licenses/miniaudio-LICENSE" "https://raw.githubusercontent.com/nyosegawa/speech.cpp/v$VERSION/vendor/miniaudio/LICENSE"
curl -fsSL -o "$TMP/out/licenses/cpp-httplib-LICENSE" "https://raw.githubusercontent.com/nyosegawa/speech.cpp/v$VERSION/vendor/cpp-httplib/LICENSE"
curl -fsSL -o "$TMP/out/licenses/ggml-LICENSE" "https://raw.githubusercontent.com/$GGML_REPO/$GGML_COMMIT/LICENSE"
echo "$VERSION" > "$TMP/out/VERSION"

rm -rf "$DEST"
mkdir -p "${DEST:h}"
mv "$TMP/out" "$DEST"
echo "speech.cpp $VERSION: $DEST/speech"
