# 開発

ソースからのビルド、開発用のコマンド、配布する版の作り方です。

## ソースからビルドする

```sh
./scripts/build-app.sh            # build/Koebumi.app を作る（Apple Development 証明書で署名）
open build/Koebumi.app
# または ~/Applications に入れて起動する
./scripts/build-app.sh --install
```

初回起動時のセットアップ画面で、次の 3 つを行います。

1. マイクへのアクセスを許可する
2. システム設定 > プライバシーとセキュリティ > アクセシビリティ で Koebumi をオンにする
3. システム設定 > キーボード の「🌐キーを押して」を「何もしない」にする

以前の名前（Speak）で使っていた場合、設定・履歴・辞書・学習内容・API キーは初回の起動で Koebumi に写します（`Core/Storage.swift`）。API キーはキーごとにキーチェーンへのアクセスを確認されます。マイクとアクセシビリティは、アプリの識別子が変わったので許可し直してください。写し終えたら `~/Applications/Speak.app` と `~/Library/Application Support/Speak` は消して構いません。

必要な環境は macOS 26 以降（開発・確認は macOS 27）と Xcode 26 以降です。Apple のオンデバイス整形を使うには Apple Intelligence をオンにしてください。

この Mac で動かす音声認識モデル（MLX）の Metal シェーダーをビルドするため、初回だけ Metal Toolchain を入れてください（約 840 MB）。

```sh
xcodebuild -downloadComponent MetalToolchain
```

## 開発

```sh
swift build
swift test                       # ショートカット判定、辞書の自動学習、表記の統一、出力の検証、プロンプト、画面の文脈、音声認識モデルの選択と読み込み、文体の学習、Claude Code・Codex の判定、送信・スラッシュコマンド・許可の確認・ファイル名の扱い、SSH 先のコマンドの読み込み、サブスクのエンジンの呼び出し、メールの返信先と定型文、AI の整形の取り消し、辞書のコマンドと Claude Code のスキル、録音しながらの書き起こしなど 264 件のテスト

# メニューバーアプリを起動せずに、音声ファイルで認識と整形を試す
say -v Kyoko -o /tmp/t.aiff "えーと、明日の会議は3時に、いや4時にしてください"
.build/debug/Koebumi --transcribe /tmp/t.aiff --category chat --app Slack
.build/debug/Koebumi --transcribe /tmp/t.aiff --stt local --stt-model qwen3-asr-0.6b --llm none   # この Mac のモデルで認識だけ試す（ダウンロード済みのモデル）
.build/debug/Koebumi --transcribe /tmp/t.aiff --stt local --stt-model qwen3-asr-0.6b --llm none --stream   # 録音しながら書き起こす。音声を実際の速さで流し、途中の書き起こしと、まとめて認識したときとの時間・結果の違いを表示する
.build/debug/Koebumi --transcribe /tmp/t.aiff --mode translate --target en-US
ANTHROPIC_API_KEY=sk-... .build/debug/Koebumi --transcribe /tmp/t.aiff --llm claude --model claude-haiku-5-5
.build/debug/Koebumi --transcribe /tmp/t.aiff --llm claudeCode --model claude-haiku-5-5   # Claude のサブスク（Claude Code にログイン済みのとき）
.build/debug/Koebumi --transcribe /tmp/t.aiff --llm codex --model gpt-6-luna              # ChatGPT のサブスク（codex login 済みのとき）

# 音声なしで整形だけを試す（--vocab の "=" は聞き取られ方の置き換え、"~" は AI へのヒント。--verbose は使わなかった AI の出力を表示）
.build/debug/Koebumi --polish "で、明日は 9時集合ですけど、違う 9時半に集合してください。" --json --prewarm
.build/debug/Koebumi --polish "クロードコードで直しました" --vocab "Claude Code=クロードコード,田中~棚香" --verbose
# 日本語の表記・敬語・画面の文脈を、変更前の設定と比べて採点する（ケースは eval/ja-cases.json）
.build/debug/Koebumi --eval eval/ja-cases.json --trials 3
# 最前面の入力欄と画面から読める文字列（メールなら、読めた返信先の宛名と、社外か社内か）を表示する。--context-demo は整形した結果を入力欄に入力する
.build/debug/Koebumi --read-context --delay 3
# --app は最前面でないアプリを読む。--masked は文字を種類（漢・あ・カ・a・0）に置き換え、挨拶・敬称などの手がかりの語だけを残す（メールの中身を見せずに、読み取りの不具合を調べるとき）
.build/debug/Koebumi --read-context --app com.apple.mail --masked
.build/debug/Koebumi --context-demo "えーと、わたなべさんに共有しておきます" --delay 3 --category chat
# 最前面の端末で Claude Code・Codex が動いているかと、作業フォルダ・ファイル数・スラッシュコマンドを表示する（--screen は保存した画面の文字列で試す）
.build/debug/Koebumi --detect-agent --delay 3
.build/debug/Koebumi --detect-agent --screen /tmp/screen.txt
# Claude Code に話したときの仕上がり（「送信」「スラッシュ 〜」も扱う。--dir の作業フォルダの .claude にある自作のコマンドも探す）
.build/debug/Koebumi --polish "README の制限事項を直して。送信" --app "Claude Code" --category ai
.build/debug/Koebumi --polish "スラッシュ コードレビュー" --app "Claude Code" --category ai --dir .
.build/debug/Koebumi --polish "スラッシュ グリルミー" --app "Claude Code" --category ai --ssh mercury   # SSH 先のスキルも探す
.build/debug/Koebumi --polish "いいえ、先にビルドして" --app "Claude Code" --category ai --screen /tmp/screen.txt --json   # 保存した画面の許可の確認で、どれを選ぶか
.build/debug/Koebumi --polish "エージェントインプットを直して" --app "Claude Code" --category ai --dir . --json   # 作業フォルダのファイル名に直す（--ssh HOST --dir PATH で SSH 先）
.build/debug/Koebumi --answer-prompt "はい" --delay 3   # 最前面の Claude Code の許可の確認に、話す代わりに文字で答える

# 各画面を PNG に書き出す（画面収録の許可なしで UI を確認する）
.build/debug/Koebumi --snapshot /tmp/koebumi-snapshots
.build/debug/Koebumi --snapshot /tmp/koebumi-snapshots --dark --en --only home   # ダーク・英語・1 画面だけ（--width 900 で最小幅）
.build/debug/Koebumi --snapshot /tmp/koebumi-snapshots --only voicebar          # 音声バーの各状態だけ
.build/debug/Koebumi --snapshot /tmp/koebumi-snapshots --only mail              # 定型文のシートと、履歴の AI の変更の表示だけ

# Claude Code のスキルが使う辞書のコマンド。ふだんのデータを書き換えずに試すときは、CFFIXED_USER_HOME で置き場所を別のフォルダにする
CFFIXED_USER_HOME=/tmp/koebumi-home .build/debug/Koebumi --dictionary add "DictationController=ディクテーションコントローラー|ディクテーションコントローラ" "Koebumi=コエブミ"
CFFIXED_USER_HOME=/tmp/koebumi-home .build/debug/Koebumi --dictionary list --json
CFFIXED_USER_HOME=/tmp/koebumi-home .build/debug/Koebumi --dictionary remove Koebumi
.build/debug/Koebumi --dictionary skill   # スキルの文面（Codex などほかのエージェントに渡すとき）
```

| ディレクトリ | 内容 |
|---|---|
| `Core/` | 設定、モデル定義、`DictationController`（録音 → 認識 → 整形 → 入力の流れ） |
| `Input/` | ショートカットの判定（`HotkeyEngine` は純粋なステートマシン）と CGEventTap |
| `Audio/` | 録音（16 kHz モノラル）、マイク一覧、出力ミュート、WAV |
| `Speech/` | Apple SpeechAnalyzer、この Mac で動かすモデル（speech-swift）、OpenAI 互換の音声認識 |
| `AI/` | プロンプト、Claude、Claude Code・Codex（サブスク）、OpenAI 互換、Apple Foundation Models |
| `System/` | 貼り付け・選択テキストの取得、アプリ判定、辞書の自動学習、辞書に語を足す Claude Code のスキル、権限、claude・codex コマンドの検索と実行、自動アップデート |
| `Data/` | 履歴、辞書、パーソナライズ、統計の保存 |
| `UI/` | 音声バー、回答カード、メインウィンドウの各画面 |

## 配布

```sh
./scripts/release.sh 0.1.0   # build/release/ に zip・appcast.xml・リリースノートを作り、GitHub Releases に上げるコマンドを表示する
```

- 署名は Apple Development の証明書です。公証していないので、試す人は最初の 1 回だけ、システム設定 > プライバシーとセキュリティ で「このまま開く」を押します（手順はリリースノートに入ります）。証明書が同じなので、版を上げてもアクセシビリティの許可は外れません
- バージョンは `release.sh` に渡した値、ビルド番号はコミット数です。Sparkle はビルド番号で新しい版かどうかを決めます。`build-app.sh` だけで作った開発用のアプリは、最新のタグのバージョンを表示します
- 自動アップデートは [Sparkle](https://sparkle-project.org) です（`System/Updater.swift`）。アプリは最新のリリースに添付した `appcast.xml` を見に行きます（`https://github.com/koebumi/koebumi/releases/latest/download/appcast.xml`）
- zip は EdDSA の鍵で署名します。秘密鍵はこの Mac のキーチェーン（アカウント名 `koebumi`）にだけあり、なくすと今のアプリに新しい版を届けられなくなります。`.build/artifacts/sparkle/Sparkle/bin/generate_keys --account koebumi -x <ファイル>` で書き出して、パスワードマネージャーなどに保管してください
