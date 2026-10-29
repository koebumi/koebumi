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
  src/Koebumi.Cli/           # net10.0-windows。開発用のコマンド koebumi.exe（--polish・--transcribe・--eval・--read-context）
  tests/Koebumi.Core.Tests/  # net10.0。Mac 版のテストを移したもの
```

`Koebumi.Core` は Windows の API を使わないので、Mac でも `dotnet build`・`dotnet test` が通ります。Windows の実機が要るのは `Koebumi.App` だけです。名前の読み（`JapanesePhoneticAnalyzer`）のように Windows の API が要る処理は、`Koebumi.Core` にインターフェースだけを置き、`Koebumi.App` で実装します。テストでは偽の実装を使います。

GitHub Actions の `windows-latest` で、両方のビルドと `Koebumi.Core.Tests` を動かします。

## Mac 版との対応

| Mac 版 | Windows 版 | フェーズ |
|---|---|---|
| ショートカット（`Input/HotkeyManager.swift`、CGEventTap） | 低レベルのキーボードフック（`SetWindowsHookEx` の `WH_KEYBOARD_LL`）。Ctrl を先に押したら Win を飲み込み、Win を先に押したら離す前に割り当てのないキー（0xE8）を挟む。飲み込んだ Win を押したままショートカット以外のキー（Ctrl+Win+← など）が来たら、Win の押下とそのキーを 1 回の SendInput で送り直す。判定の `Input/HotkeyEngine.swift` はそのまま移す | 1 |
| 録音（`Audio/AudioRecorder.swift`、16 kHz モノラル） | NAudio（WASAPI）で録音し、16 kHz モノラルに変換する | 1 |
| マイク一覧・入力中のミュート（`Audio/AudioDevices.swift`） | NAudio の `MMDeviceEnumerator` と `AudioEndpointVolume` | 1（ミュートは 2） |
| 音声認識（`Speech/Transcriber.swift`） | OpenAI 互換の `/audio/transcriptions`（OpenAI・Groq・カスタム）だけにする | 1 |
| 整形（`AI/ClaudeEngine.swift`・`AI/OpenAICompatibleEngine.swift`・`AI/Polisher.swift`） | `HttpClient` で同じ API を呼ぶ。プロンプトは `AI/Prompts.swift` から写す | 1 |
| 貼り付け（`System/TextInserter.swift`） | クリップボードに入れて `SendInput` で Ctrl+V を送り、600 ms 後にクリップボードを元に戻す。修飾キーをすべて離してから送る。貼り付ける文と戻す内容には、履歴に残さない形式を付ける | 1 |
| アプリの分類（`System/AppContext.swift`、バンドル ID） | 最前面の窓の exe 名（`OUTLOOK.EXE`・`olk.exe`・`slack.exe` など）とウィンドウタイトル。分類の表は Windows 用に作り直す | 1 |
| API キー（`Core/Keychain.swift`） | 資格情報マネージャー（`CredWrite`・`CredRead`） | 1 |
| 保存（`Core/Storage.swift`・`Data/`） | `%APPDATA%\Koebumi` に、Mac 版と同じ形の JSON で保存する | 1 |
| 選択テキストの取得（Ask anything の書き換え） | UI Automation の `TextPattern.GetSelection`。読めないアプリでは Ctrl+C で取る | 2 |
| 自動アップデート（Sparkle） | Velopack（GitHub Releases） | 2 |
| 画面の文脈（`System/SurroundingText.swift`） | COM の UI Automation で、`TextPattern2.GetCaretRange`（なければ `TextPattern.GetSelection`）からカーソルの前後を入力欄の範囲で読む。窓の文字は、要素の木を 1 回でまとめて写して（`BuildUpdatedCache`）たどる。名前の読みは `Windows.Globalization.JapanesePhoneticAnalyzer` | 3 |
| メールの返信先（`AI/MailReply.swift`） | 判定はそのまま移す。読み取りは画面の文脈と同じ | 3 |
| AI の整形を元に戻す | UI Automation で、入力した文がカーソルの直前にあると確かめてから選び直す | 3 |
| 辞書の自動追加（`System/CorrectionWatcher.swift`） | UI Automation で入力欄を 1 秒ごとに読む | 3 |
| 画面（`UI/`） | WPF で作り直す。音声バーは `ShowActivated = false` と `WS_EX_NOACTIVATE` で、フォーカスを奪わない | 1〜2 |

Windows 版に入れないもの: Apple の音声認識、この Mac で動かすモデル（MLX は Apple silicon 専用）、Apple のオンデバイス整形、Dock の表示。Mac 版の権限の画面（アクセシビリティ）は要りません。マイクは、設定 > プライバシーとセキュリティ > マイク の「デスクトップ アプリがマイクにアクセスできるようにする」がオフのときだけ案内します。

## 作る順番

### フェーズ 0: 実機で確かめる（2〜3 日）

Windows の実機で小さな試作を作り、次を確かめます。どれかが駄目なら、この設計を直します。

1. キーボードフックで、ショートカットを押したときと離したときを取れるか。取ったキーを入力先のアプリに渡さずに済むか（Win キーを使うなら、スタートメニューが開かないか）
2. 音声バーを出しても、入力先のアプリのフォーカスが外れないか
3. Ctrl+V の貼り付けが、日本語入力がオンのときも入るか（メモ帳・Word・Chrome・Edge・Slack・Teams・Outlook の新旧）
4. UI Automation で、同じアプリと Gmail（Chrome）のカーソル前後の文字とウィンドウの文章を、0.3 秒以内に読めるか
5. 管理者として動いているアプリ（管理者のターミナルなど）には、フックも貼り付けも届かない（UIPI）。そのときに知らせられるか

2026-10-27 に確かめました。結果は [docs/research/windows-phase0.md](research/windows-phase0.md)、試作は [`windows/spikes/Phase0`](../windows/spikes/Phase0/README.md) です。

- 5 項目とも、設計の方針を変えるような問題はありませんでした。わかったことは、この文書の各所に反映しました
- 試せなかったもの: Word と Outlook（クラシック）は、使った PC の Office がライセンス認証されておらず、編集できませんでした。Teams・新しい Outlook・Gmail は試していません。PC に直接つないだキーボードでも試していません（リモート デスクトップ経由で試しました）。フェーズ 1 の確認と一緒に試します

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

2026-10-28 時点では、上の項目をすべて作り、次を確かめました。

- `Koebumi.Core` に、Mac 版の Foundation だけのコードとそのテストを移しました（テスト 310 件）。Mac 版の保存形式（`settings.json` など）のまま読み書きします
- アプリの自己テスト（`Koebumi.App.exe --selftest`）で、人が操作しなくてよい部分を確かめました。資格情報マネージャー、録音、日本語の読み、クリップボードの退避と戻し、ショートカットの判定、偽の音声認識と整形を使った録音から入力までの流れです
- 整形は、本物のモデル（Gemini の `gemini-2.5-flash`）で `koebumi.exe --polish` を動かし、ドキュメントでは「明日の会議は4時にしてください。」、チャットでは「明日の会議は4時にしてください」になりました
- 終わりの確認: 話す代わりに、Windows の読み上げ（Haruka）で作った音声をマイクの代わりに流して（環境変数 `KOEBUMI_FAKE_AUDIO`）確かめました。音声認識はローカルの whisper.cpp、整形は Claude（`claude-haiku-5-5`）です。メモ帳には「明日の会議は4時にしてください。」、Slack（自分あての DM）には「明日の会議は4時にしてください」が入りました。ショートカット（左 Alt + 左 Win の長押し）は SendInput で送りました
- 実際のマイクで話して入力できることは、2026-10-29 に使う人が確かめました
- Windows 11 では、トレイのアイコンが「^」の中に隠れて見つけにくいので、音声認識か整形に要る API キーがないときは起動時に設定の画面を開きます。もう一度起動したときは、動いているほうが設定の画面を開きます
- わかったこと: 入力欄にフォーカスがないとき（Slack でスレッドの一覧を開いているときなど）は、Ctrl+V を送っても何も入りませんが、Koebumi は入力できたものとして扱います。Mac 版は入力欄がないとクリップボードにコピーして知らせるので、フェーズ 3 の UI Automation の作業で、入力欄があるかを見分けます
- まだ確かめていないもの: ショートカットの記録、変換中の Enter での確定

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
- 2026-10-28 に、whisper.cpp のサーバーで動くことを確かめました。公式リリースの Windows 用 CUDA 版（v1.9.5 と同じ日のビルド b5454 の `whisper-bin-win-cuda-12.4.0-x64.zip`）と、モデル `ggml-large-v3-turbo.bin`（約 1.6 GB）を使います
  - 起動: `whisper-server.exe -m ggml-large-v3-turbo.bin --host 127.0.0.1 --port 8178 --inference-path /v1/audio/transcriptions -l auto`。Koebumi の設定は「カスタム（OpenAI 互換）」、URL は `http://127.0.0.1:8178/v1`
  - `--inference-path` を付けないと、パスが `/inference` になり、OpenAI 互換の呼び出しが 404 になります。`-l` の既定は `en` なので、言語を送らない呼び出し（話す言語を 2 つ以上選んだとき）のために `auto` にします
  - Git Bash から起動するときは `MSYS_NO_PATHCONV=1` を付けます。付けないと `/v1/audio/transcriptions` が `C:/Program Files/Git/v1/...` に書き換わります
  - RTX 6000 Ada で、5 秒の音声を 0.13〜0.3 秒で書き起こしました

## Mac 版と同じ動きにする

- `Koebumi.Core` に処理を移すときは、その処理のテスト（`Tests/KoebumiTests/`）も C# に移します
- Windows 版にも `--polish` と `--eval` のコマンドを作り、`eval/ja-cases.json` を Mac 版と Windows 版の両方で採点します。Windows 版は `koebumi.exe`（`src/Koebumi.Cli`）です。API キーは資格情報マネージャーを先に見て、なければ `OPENAI_API_KEY` などの環境変数を使います
- プロンプトを変えるときは、Mac 版と Windows 版の両方を変えます。ずれが問題になったら、プロンプトを共通のファイルに出すことを考えます

## 開発の環境

- Windows 版は、Windows の実機にこのリポジトリをクローンして開発します。`Koebumi.Core` も含めて Windows で書けば、マシンを行き来せずに済みます
- WSL ではなく、Windows の上で直接開発します。WPF のビルド、キーボードのフック、UI Automation は Windows 側でしか動かないためです
- 移すときに読む Mac 版のソースとテストは、同じリポジトリにあります。Swift のテストは Windows では動かないので、期待する値はテストのコードから写します。`eval/ja-cases.json` の Mac 版の採点は Mac で動かします
- 改行は LF にそろえます（`.gitattributes`）。Git for Windows の既定では、チェックアウトしたファイルが CRLF になるためです
- .NET 10 の SDK を入れます。フェーズ 0 の PC には .NET 9 の SDK しかなかったので、試作は .NET 9 で作りました。フェーズ 1 では、SDK をユーザーのフォルダ（`%LOCALAPPDATA%\Microsoft\dotnet`）に入れました。この場合、ビルドした exe は環境変数 `DOTNET_ROOT` にそのフォルダを指定しないと起動できません。指定せずに動かすときは、.NET を同梱して発行します（`dotnet publish src/Koebumi.App -c Release -r win-x64 --self-contained -o src/Koebumi.App/bin/publish`）
- キー入力を送る試験は、リモート デスクトップのセッションをつないだまま行います。切断すると SendInput が失敗し、Chrome はページの中身を UI Automation に出しません

## 配布

- 最初は署名しないまま、Velopack で作ったインストーラーを GitHub Releases に置きます。初回は SmartScreen の「Windows によって PC が保護されました」が出るので、「詳細情報」→「実行」を押してもらいます（手順はリリースノートに入れます）
- コード署名（Microsoft の Trusted Signing など）は、使う人が増えたら決めます

## 気をつけること

- 管理者権限で動くアプリには、フックも貼り付けも届きません（UIPI）。そのアプリが前面のあいだは、ショートカットを押したことにも気づけません。前面の切り替え（`SetWinEventHook` の `EVENT_SYSTEM_FOREGROUND`）を受け取り、前面のプロセスの整合性レベルが自分より上なら、音声バーで「管理者として動いているアプリには入力できません」と知らせます。SendInput はこのとき、エラーを返さずにキーを捨てます
- 貼り付けに使った文と、戻した元の内容が、クリップボードの履歴（Win+V）とクラウドのクリップボードに残らないように、`ExcludeClipboardContentFromMonitorProcessing`・`CanIncludeInClipboardHistory`（0）・`CanUploadToCloudClipboard`（0）の 3 つの形式を一緒に入れます（フェーズ 0 で効くことを確かめました）
- 日本語入力で変換している途中に貼り付けると、アプリによって結果が違います。メモ帳は未確定の文字を確定してから貼り付けますが、Chrome・Edge は未確定のまま残してその後ろに貼り付け、そのあと Esc を押すと未確定の文字が消えます。未確定の文字は UI Automation の `TextEditPattern.GetActiveComposition` で見分けられるので、扱いを決めます（「決めること」の 4）
- Chromium のアプリ（Chrome・Edge と、Slack などの Electron）は、UI Automation の問い合わせを受けてからページの木を作ります。最初の読み取りでフォーカスが外側の枠を指したら、30 ms 待って取り直します（取り直しは 1〜2 回で、全体で 0.15 秒以内でした）。また、カーソルの前後を文字数で広げると入力欄を越えてページの文字まで入るので、入力欄の `DocumentRange` の端で切ります
- Win を先に押したときは、Win を入力先のアプリから取り消せません。貼り付けの Ctrl+V は、修飾キーをすべて離してから送ります（Win を押したままだと Win+Ctrl+V になります。Windows 11 では音の出力の切り替えを開くショートカットです。これは試していません）

## 決めること

1. 既定のショートカット。Windows では Fn キーを取れません。候補は Ctrl+Win（どのキーボードにもある）、右 Ctrl（Copilot キーに置き換わって、ないノート PC がある）、無変換（日本語キーボードだけ）です。案は Ctrl+Win です。フェーズ 0 では 3 つとも、押したときと離したときを取れて、入力先のアプリに渡さずに済みました
2. 開発に使う Windows の実機。フェーズ 0 はリモート デスクトップでつないだ PC で行いました。その PC の Office はライセンス認証されていないので、Word・Outlook（クラシック）を試すには認証するか、別の PC が要ります
3. Claude・ChatGPT のサブスクを使う整形を、フェーズ 2 に入れるか
4. 変換中（未確定の文字がある）に貼り付けるときの扱い。案は、`GetActiveComposition` で未確定の文字があるときだけ Enter を送って確定させてから貼り付けることです。フェーズ 1 では、この案のとおりに作りました（Enter で確定できるかは、まだ試していません）
