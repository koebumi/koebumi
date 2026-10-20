# Speak

Typeless と同じ使い方ができる macOS 用の AI 音声入力アプリです。どのアプリでも Fn キーを押して話すと、フィラーや言い直しを取り除いた文章がカーソル位置に入力されます。

キーがなくても Apple のオンデバイスモデル（音声認識と文章整形）で動きます。Claude や OpenAI 互換 API などの自分の API キー（BYOK）も使えます。

## 使い方

| 操作 | 既定のショートカット | 内容 |
|---|---|---|
| ディクテーション | `Fn` | 短く押すとハンズフリーになり、もう一度押すと確定します。押し続けて話すと、離したときに確定します（プッシュトゥトーク） |
| 翻訳 | `Fn + Left ⇧` | 話した内容を翻訳先の言語で入力します。翻訳先は音声バーで切り替えられます |
| Ask anything | `Fn + Space` | テキストを選択してから「もっと丁寧に」などと話すと書き換えます。選択中のテキストについて質問すると、カードで回答します。選択なしで質問した場合もカードで回答し、「YouTube で猫の動画」のような依頼ならページを開きます |
| キャンセル | `Esc` | 録音・処理を止めます。回答カードも閉じます |

Fn を押したまま話している途中で Shift や Space を足すと、録音を続けたまま翻訳・Ask に切り替わります。ショートカットは設定画面で変更でき、1 つの操作に複数登録できます。

## セットアップ

```sh
./scripts/build-app.sh            # build/Speak.app を作る（Apple Development 証明書で署名）
open build/Speak.app
# または ~/Applications に入れて起動する
./scripts/build-app.sh --install
```

初回起動時のセットアップ画面で、次の 3 つを行います。

1. マイクへのアクセスを許可する
2. システム設定 > プライバシーとセキュリティ > アクセシビリティ で Speak をオンにする
3. システム設定 > キーボード の「🌐キーを押して」を「何もしない」にする

必要な環境は macOS 26 以降（開発・確認は macOS 27）と Xcode 26 以降です。Apple のオンデバイス整形を使うには Apple Intelligence をオンにしてください。

## Typeless の機能との対応

| Typeless の機能 | Speak での実装 |
|---|---|
| フィラー除去・繰り返し除去・言い直しの反映 | LLM で整形する（`AI/Prompts.swift`）。LLM が使えないときは正規表現による簡易整形を行う |
| 箇条書き・手順の自動整形 | 列挙を検出してリストにする。「改行」「段落」などの音声コマンドにも対応 |
| アプリごとのトーン | 入力先アプリ（ブラウザはウィンドウタイトルの Gmail・Slack など）を 6 種類に分類する。種類ごとにトーンを指定でき、アプリの分類は上書きできる |
| パーソナライズ | 6 回話すごとに文体（丁寧さ・詳しさ・癖）を抽象的に学習する。進捗とレポートを表示し、オン・オフとリセットができる。内容そのものは保存しない |
| 個人辞書 | 手動追加、CSV の取り込みと書き出し、検索、絞り込み（すべて・自動・手動）、編集、削除。単語は音声認識のヒントと表記指定に使う |
| 辞書の自動追加 | 入力後 1 分以内にユーザーが単語を直すと、それを検出して辞書に追加する（`System/CorrectionWatcher.swift`） |
| 翻訳モード | 翻訳先リスト（並べ替え可）と、音声バーでの切り替え |
| Ask anything | 選択テキストの書き換え、質問への回答カード、カーソル位置への入力、Web ページを開く。Claude 使用時は Web 検索にも対応 |
| 100 以上の言語・自動判定・混在した発話 | クラウドの音声認識（OpenAI・Groq）では自動判定する。Apple の音声認識は選んだ言語で認識し、録音中に切り替えられる |
| 言語のバリアント | 英語 US/UK、中国語 簡体/繁体、ポルトガル語 BR/PT などを選べる |
| 履歴 | 絞り込み（すべて・ディクテーション・Ask）、検索、コピー、フィードバック、再処理、音声のダウンロード、削除、すべて削除。保存期間は無期限・1年・1か月・1週間・24時間・保存しない から選べる |
| 統計 | 単語数、節約した時間、平均 WPM、連続日数、30 日間のグラフ |
| 設定 | マイク選択とテスト、インタラクションサウンド、入力中のミュート、表示言語（日本語・英語）、外観、ログイン時に起動、Dock 表示 |
| プライバシー | 履歴・音声・辞書・学習内容はこの Mac の中だけに保存する。API キーはキーチェーンに保存する |

## AI エンジン（BYOK）

設定 > AI エンジン で選びます。

**音声認識**
- Apple オンデバイス（既定・キー不要・オフライン）。録音しながら逐次認識するので、話し終えてから約 0.5 秒で結果が出る
- OpenAI（`gpt-4o-transcribe`）
- Groq（`whisper-large-v3-turbo`）
- カスタム（OpenAI 互換の `/audio/transcriptions`。ローカルの Whisper サーバーなど）

**文章整形・翻訳・Ask anything**
- Apple オンデバイス（既定・キー不要）。整形は約 0.5〜1.5 秒
- Claude（`claude-opus-5-5` が既定。Sonnet 5.5 / Haiku 5.5 も選べる）。安全性フィルタで断られたときは、サーバー側で推奨モデルに切り替える `fallbacks: "default"` を有効にしている
- OpenAI 互換: OpenAI、Groq、OpenRouter、Gemini、Ollama（ローカル・キー不要）、カスタム URL。モデル名とベース URL は書き換えられる
- 整形しない（簡易整形のみ）

## 開発

```sh
swift build
swift test                       # ショートカット判定、辞書の自動学習、WAV、プロンプトなど 26 件のテスト

# メニューバーアプリを起動せずに、音声ファイルで認識と整形を試す
say -v Kyoko -o /tmp/t.aiff "えーと、明日の会議は3時に、いや4時にしてください"
.build/debug/Speak --transcribe /tmp/t.aiff --category chat --app Slack
.build/debug/Speak --transcribe /tmp/t.aiff --mode translate --target en-US
ANTHROPIC_API_KEY=sk-... .build/debug/Speak --transcribe /tmp/t.aiff --llm claude --model claude-haiku-5-5

# 各画面を PNG に書き出す（画面収録の許可なしで UI を確認する）
.build/debug/Speak --snapshot /tmp/speak-snapshots
.build/debug/Speak --snapshot /tmp/speak-snapshots --dark --en --only home   # ダーク・英語・1 画面だけ（--width 900 で最小幅）
```

| ディレクトリ | 内容 |
|---|---|
| `Core/` | 設定、モデル定義、`DictationController`（録音 → 認識 → 整形 → 入力の流れ） |
| `Input/` | ショートカットの判定（`HotkeyEngine` は純粋なステートマシン）と CGEventTap |
| `Audio/` | 録音（16 kHz モノラル）、マイク一覧、出力ミュート、WAV |
| `Speech/` | Apple SpeechAnalyzer と OpenAI 互換の音声認識 |
| `AI/` | プロンプト、Claude、OpenAI 互換、Apple Foundation Models |
| `System/` | 貼り付け・選択テキストの取得、アプリ判定、辞書の自動学習、権限 |
| `Data/` | 履歴、辞書、パーソナライズ、統計の保存 |
| `UI/` | 音声バー、回答カード、メインウィンドウの各画面 |

## 制限事項

- 対応 OS は macOS だけです。Windows・Linux・iOS・Android 版と、端末間の暗号化同期はありません。
- Apple Private Cloud Compute は Apple の申請制 entitlement が必要なため使っていません。
- Web 検索は Claude を選んだときだけ使えます。
- Apple のオンデバイスモデルは小型なので、複雑な言い直しの解消や翻訳の自然さは Claude などに劣ります。
- 表示言語は日本語と英語だけです。
