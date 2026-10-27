# Windows 版の設計

Windows 版 Koebumi の作り方と、作る順番です。2026-10-27 時点の案で、まだ決めていないことは最後の「決めること」にまとめました。

## 前提

- 対象は普通の Windows 11 の PC（x64）です。NPU は前提にしません
- API キーなしで動くことは求めません。そのかわり、自分で動かすローカルモデル（Ollama・LM Studio など）とクラウドの API を、設定で選んで使えるようにします
- Claude Code・Codex の操作（エージェントの見分け、スラッシュコマンド、許可の確認への返事、ファイル名の修正、「送信」）は後回しにします。それ以外の機能は最初の版から順に入れます

## 方針

- C#（.NET 10）で作り、このリポジトリの `windows/` に置きます
- Mac 版のうち Foundation だけを使うコード（約 5,600 行。プロンプト、表記の統一、言い直しの検出、ショートカットの判定、定型文、メールの返信先の判定など）を C# に移します。テストも一緒に移し、Mac 版と同じ入力で同じ結果になることを確かめます
- 画面は WPF で作ります（理由は下）
- 音声認識と整形は OpenAI 互換の API で呼びます。OpenAI・Groq のほか、自分の PC で動かすサーバーも同じ形で呼べます

Mac 版の残りの約 11,600 行は、AppKit・SwiftUI・アクセシビリティ API・Apple の音声認識などを使うので、Windows の API で書き直します。

### 画面を WPF にする理由

- 音声バーは、最前面に出て、入力先のアプリからフォーカスを奪わない透明な窓にする必要があります。WPF は透明な窓（`AllowsTransparency`）をそのまま作れ、フォーカスを奪わない設定（`WS_EX_NOACTIVATE`）も Win32 の呼び出し 1 つで足ります。WinUI 3 は透明な窓を作るのに手間がかかります
- インストーラーなしの exe で配れ、Velopack で自動アップデートできます
- .NET 9 から、Windows 11 に合う Fluent のテーマが入りました
- 例や情報が多いので、Claude Code で書いても詰まりにくいです

## プロジェクトの構成

```
windows/
  Koebumi.Windows.sln
  src/Koebumi.Core/          # net10.0。Mac 版から移す処理（整形・表記・プロンプト・ショートカットの判定・保存の形式）
  src/Koebumi.App/           # net10.0-windows。WPF の画面、録音、キーボードのフック、貼り付け、UI Automation
  tests/Koebumi.Core.Tests/  # net10.0。Mac 版のテストを移したもの
```

`Koebumi.Core` は Windows の API を使わないので、Mac でも `dotnet build`・`dotnet test` が通ります。Windows の実機が要るのは `Koebumi.App` だけです。名前の読み（`JapanesePhoneticAnalyzer`）のように Windows の API が要る処理は、`Koebumi.Core` にインターフェースだけを置き、`Koebumi.App` で実装します。テストでは偽の実装を使います。

GitHub Actions の `windows-latest` で、両方のビルドと `Koebumi.Core.Tests` を動かします。

## Mac 版との対応

| Mac 版 | Windows 版 | フェーズ |
|---|---|---|
| ショートカット（`Input/HotkeyManager.swift`、CGEventTap） | 低レベルのキーボードフック（`SetWindowsHookEx` の `WH_KEYBOARD_LL`）。判定の `Input/HotkeyEngine.swift` はそのまま移す | 1 |
| 録音（`Audio/AudioRecorder.swift`、16 kHz モノラル） | NAudio（WASAPI）で録音し、16 kHz モノラルに変換する | 1 |
| マイク一覧・入力中のミュート（`Audio/AudioDevices.swift`） | NAudio の `MMDeviceEnumerator` と `AudioEndpointVolume` | 1（ミュートは 2） |
| 音声認識（`Speech/Transcriber.swift`） | OpenAI 互換の `/audio/transcriptions`（OpenAI・Groq・カスタム）だけにする | 1 |
| 整形（`AI/ClaudeEngine.swift`・`AI/OpenAICompatibleEngine.swift`・`AI/Polisher.swift`） | `HttpClient` で同じ API を呼ぶ。プロンプトは `AI/Prompts.swift` から写す | 1 |
| 貼り付け（`System/TextInserter.swift`） | クリップボードに入れて `SendInput` で Ctrl+V を送り、クリップボードを元に戻す | 1 |
| アプリの分類（`System/AppContext.swift`、バンドル ID） | 最前面の窓の exe 名（`OUTLOOK.EXE`・`olk.exe`・`slack.exe` など）とウィンドウタイトル。分類の表は Windows 用に作り直す | 1 |
| API キー（`Core/Keychain.swift`） | 資格情報マネージャー（`CredWrite`・`CredRead`） | 1 |
| 保存（`Core/Storage.swift`・`Data/`） | `%APPDATA%\Koebumi` に、Mac 版と同じ形の JSON で保存する | 1 |
| 選択テキストの取得（Ask anything の書き換え） | UI Automation の `TextPattern.GetSelection`。読めないアプリでは Ctrl+C で取る | 2 |
| 自動アップデート（Sparkle） | Velopack（GitHub Releases） | 2 |
| 画面の文脈（`System/SurroundingText.swift`） | UI Automation の `TextPattern2.GetCaretRange` と、窓の要素をたどる読み取り。名前の読みは `Windows.Globalization.JapanesePhoneticAnalyzer` | 3 |
| メールの返信先（`AI/MailReply.swift`） | 判定はそのまま移す。読み取りは画面の文脈と同じ | 3 |
| AI の整形を元に戻す | UI Automation で、入力した文がカーソルの直前にあると確かめてから選び直す | 3 |
| 辞書の自動追加（`System/CorrectionWatcher.swift`） | UI Automation で入力欄を 1 秒ごとに読む | 3 |
| 画面（`UI/`） | WPF で作り直す | 1〜2 |

Windows 版に入れないもの: Apple の音声認識、この Mac で動かすモデル（MLX は Apple silicon 専用）、Apple のオンデバイス整形、Dock の表示。Mac 版の権限の画面（アクセシビリティ）は要りません。マイクは、設定 > プライバシーとセキュリティ > マイク の「デスクトップ アプリがマイクにアクセスできるようにする」がオフのときだけ案内します。

## 作る順番

### フェーズ 0: 実機で確かめる（2〜3 日）

Windows の実機で小さな試作を作り、次を確かめます。どれかが駄目なら、この設計を直します。

1. キーボードフックで、ショートカットを押したときと離したときを取れるか。取ったキーを入力先のアプリに渡さずに済むか（Win キーを使うなら、スタートメニューが開かないか）
2. 音声バーを出しても、入力先のアプリのフォーカスが外れないか
3. Ctrl+V の貼り付けが、日本語入力がオンのときも入るか（メモ帳・Word・Chrome・Edge・Slack・Teams・Outlook の新旧）
4. UI Automation で、同じアプリと Gmail（Chrome）のカーソル前後の文字とウィンドウの文章を、0.3 秒以内に読めるか
5. 管理者として動いているアプリ（管理者のターミナルなど）には、フックも貼り付けも届かない（UIPI）。そのときに知らせられるか

### フェーズ 1: 話して、整形して、入力する（1.5〜2 週間）

Mac 版のディクテーションを一通り動かします。

- タスクトレイに常駐する。ショートカットで録音を始めて終える（押している間だけ録音するのと、押すたびに切り替えるのの両方）。Esc で取り消す
- 音声バー（録音中の音量、処理中、失敗の表示）
- 音声認識: OpenAI・Groq・カスタム（OpenAI 互換）
- 整形: Claude・OpenAI 互換（OpenAI・Groq・OpenRouter・Gemini・Ollama・カスタム）・整形しない
- フィラーの除去、言い直しの反映、表記の統一、日本語の仕上がり（句読点、英単語の前後の空白、補助動詞のひらがな）、チャットの句読点
- アプリごとのトーン（6 種類）と、アプリの分類の上書き
- 辞書（手で追加、聞き取られ方の置き換え、音声認識へのヒント）と定型文
- 設定の画面（マイク、ショートカット、AI エンジン、API キー、スタイル）

終わったかどうかは、メモ帳と Slack で「えーと、明日の会議は3時に、いや4時にしてください」と話して確かめます。メモ帳には「明日の会議は4時にしてください。」、Slack には句点のない「明日の会議は4時にしてください」が入れば終わりです。

### フェーズ 2: 翻訳・Ask anything・履歴（1〜2 週間）

- 翻訳（翻訳先の切り替え）と Ask anything（選択テキストの書き換え、回答カード、Web ページを開く）
- 履歴（検索、再処理、音声のダウンロード、AI の変更の表示）と統計
- 直前の結果をもう一度入力する、文体の学習、入力中のミュート、インタラクションサウンド
- 自動アップデートと、ログイン時の起動

### フェーズ 3: 画面を読む機能（2〜4 週間）

UI Automation で読める範囲はアプリごとに違うので、見積もりの幅が大きいです。

- 画面の文脈（敬称の前の名前を画面の表記に直す、書きかけの文の続きとしてつなぐ）
- メールの返信先に合わせた挨拶と敬称
- AI の整形を元に戻す
- 辞書の自動追加

### 後回しにするもの

- Claude Code・Codex の操作
- Claude・ChatGPT のサブスクを使う整形（`claude`・`codex` のコマンド経由）
- PC の中で動かす音声認識（whisper.cpp などをアプリに組み込む）。それまでは、自分で立てたサーバーを「カスタム」で使います

## 自分で動かすモデルを使う

- 整形: Ollama（`http://localhost:11434/v1`）と LM Studio（`http://localhost:1234/v1`）を、Mac 版と同じく OpenAI 互換の Chat Completions で呼びます
- 音声認識: OpenAI 互換の `/v1/audio/transcriptions` を持つサーバー（speaches、LocalAI など）を立てて、「カスタム」に URL を入れます。速さは PC によって大きく変わるので、フェーズ 1 で実機で測ります

## Mac 版と同じ動きにする

- `Koebumi.Core` に処理を移すときは、その処理のテスト（`Tests/KoebumiTests/`）も C# に移します
- Windows 版にも `--polish` と `--eval` のコマンドを作り、`eval/ja-cases.json` を Mac 版と Windows 版の両方で採点します
- プロンプトを変えるときは、Mac 版と Windows 版の両方を変えます。ずれが問題になったら、プロンプトを共通のファイルに出すことを考えます

## 開発の環境

- Windows 版は、Windows の実機にこのリポジトリをクローンして開発します。`Koebumi.Core` も含めて Windows で書けば、マシンを行き来せずに済みます
- WSL ではなく、Windows の上で直接開発します。WPF のビルド、キーボードのフック、UI Automation は Windows 側でしか動かないためです
- 移すときに読む Mac 版のソースとテストは、同じリポジトリにあります。Swift のテストは Windows では動かないので、期待する値はテストのコードから写します。`eval/ja-cases.json` の Mac 版の採点は Mac で動かします
- 改行は LF にそろえます（`.gitattributes`）。Git for Windows の既定では、チェックアウトしたファイルが CRLF になるためです

## 配布

- 最初は署名しないまま、Velopack で作ったインストーラーを GitHub Releases に置きます。初回は SmartScreen の「Windows によって PC が保護されました」が出るので、「詳細情報」→「実行」を押してもらいます（手順はリリースノートに入れます）
- コード署名（Microsoft の Trusted Signing など）は、使う人が増えたら決めます

## 気をつけること

- 管理者権限で動くアプリには、フックも貼り付けも届きません（UIPI）
- 貼り付けに使ったクリップボードの内容が、クリップボードの履歴（Win+V）に残らないようにします。Windows には履歴から除くためのクリップボード形式があるので、フェーズ 0 で効くか確かめます
- 日本語入力で変換している途中に貼り付けたときの動きを、フェーズ 0 で確かめます

## 決めること

1. 既定のショートカット。Windows では Fn キーを取れません。候補は Ctrl+Win（どのキーボードにもある）、右 Ctrl（Copilot キーに置き換わって、ないノート PC がある）、無変換（日本語キーボードだけ）です。案は Ctrl+Win です
2. 開発に使う Windows の実機
3. Claude・ChatGPT のサブスクを使う整形を、フェーズ 2 に入れるか
