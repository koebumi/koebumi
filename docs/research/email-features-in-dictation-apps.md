# 音声入力アプリの「メールを書く場面」の機能（macOS）

調査日: 2026-10-23。一次情報（各社の公式サイト・ヘルプセンター・公式ドキュメント・変更履歴、オープンソースのソース）だけを根拠にした。第三者のレビュー記事・まとめ記事・SNS は根拠にしていない。検索結果に出た第三者の記事は、一次情報をたどる手がかりにだけ使った。

各主張に「確認」か「推測」を付けた。
- 確認: 一次情報の該当箇所を読んで確かめた。
- 推測: 読んだ内容からの推論で、直接は確かめていない。

Web のページは、取得ツールが本文を要約して返す方式で読んだ（生の HTML は読んでいない）。引用は短い語句に限り、要約の言い回しが原文と違う可能性がある。ソースを読んだものは、ファイルと行を付けた。

読んだコミット（すべて shallow clone。クローンの中のコードは実行していない。ビルドもしていない）:

| 対象 | SHA |
|---|---|
| VoiceInk | `22e5ec5479b712797c3b338fcb875961e58800b6` |
| OpenWhispr | `7a6ae826de9ec1caf65f3a6e769475dab2ae829f` |
| Amical | `b98f79fb5e7f684b836d407d62878281ffc783eb` |
| Handy | `5a9451e70aedc90648ce2befd9d7e0304746f9c1` |
| Koebumi（比較用、このリポジトリ） | `0a08d02d4fcad74d2097814ff58ca40cff8d90a4` |

OpenWhispr の SHA は、前回のマイク調査（`ba6d618...`）より新しい。今回あらためて clone したため。

## 1. 要約

- 全アプリがメールを「別の場面」として扱う。見分け方は、アプリのバンドル ID と、ブラウザの URL またはウィンドウタイトルの 2 通り。ソースを読めた 3 アプリ（VoiceInk、OpenWhispr、Amical）は、どれも両方を使う。Handy にはアプリの見分けがない。
- メール向けの整形は 2 系統に分かれる。(a) 声のとおりに整える系（Amical、OpenWhispr、VoiceInk）は、話していない挨拶・署名を足さない。(b) Superwhisper の Mail モードは、挨拶・段落・結びを足すと明記している。
- 返信の文脈を使う仕組みは、画面を読む方式に偏る。Superwhisper は入力欄のテキストと選択範囲、VoiceInk は画面の OCR とクリップボード、Aqua Voice と OpenWhispr（音声アシスタント）はスクリーンショットを使う。Wispr Flow と Typeless は、入力欄の周りの文字だけを読むと説明している。
- コマンド型は多い。Wispr Flow の Command Mode と Transforms、Typeless の Ask Anything、Aqua Voice の Edit Mode、OpenWhispr の音声アシスタント（メール下書きツール付き）が、選択範囲の書き換えや下書きを行う。
- 日本語メールを明示して対応しているアプリは、見つからなかった。Wispr Flow の Styles は英語のみと明記している。OpenWhispr のトーン指示は英語で書かれている。Aqua Voice は日本語の認識精度向上と「送信」コマンドの日本語対応を告知したが、敬語や定型挨拶の話ではない。

## 2. 比較表

| | (1) メールの見分け方 | (2) メール向けの整形 | (3) 返信の文脈 | (4) コマンド型 | (5) ユーザー設定 | (6) 日本語メール |
|---|---|---|---|---|---|---|
| Typeless | アプリ別にトーンを変えると説明。見分け方は見つからなかった | トーンの個人化（使うほど学習）。メール専用の挨拶・署名の記述は見つからなかった | 「関連するテキスト」を処理に送ると説明。メールの返信専用の機能は見つからなかった | Ask Anything（書き換え、要約、下書き） | 個人化のオン/オフのみ。アプリごとの規則は見つからなかった | 言及なし |
| Wispr Flow | アプリ名。Mac・Windows・Android は Web アプリを URL でも見分ける | Styles（Email カテゴリ: Formal/Casual/Excited）。挨拶・結び・改行を整える | 周囲のテキストで人名の綴りを当てる（Android は文書で確認） | Command Mode（返信の下書き、書き換え）、Transforms | カテゴリごとの Style、スニペット、Transforms のカスタムプロンプト（最大 8 個） | Styles は英語のみ。日本語の辞書入力は可 |
| Superwhisper | 自動切り替えルール（アプリとサイト）。判定方法の詳細は見つからなかった | Mail モード（挨拶・段落・結びを足す。トーンのスライダー） | Super モードと Custom モードがアプリのテキスト、選択範囲、クリップボードを読む。氏名を AI に渡し、署名に使う | Super モードのコマンド（書式変換向け） | Custom モード（自由な指示、文脈の取捨選択、アプリ/サイトの割り当て） | 日本語メールの記述は見つからなかった |
| Aqua Voice | 「どのアプリでも動く」と説明。見分け方は見つからなかった | カスタム指示（メールの改行、署名の書き方を覚える） | Deep Context（画面全体のスクリーンショットから名前・用語を拾う） | Edit Mode（選択範囲を声で書き換える） | カスタム指示（Pro）。アプリごとの設定は見つからなかった | 日本語の認識精度向上（2026-10-06）、「送信」コマンドの日本語対応 |
| Willow Voice | アプリごとのスタイル（Gmail、Outlook、Apple Mail）。見分け方は書かれていない | Email プリセット（Default/Casual Friendly/Excited）。挨拶・本文・結びを分け、改行を入れる | 「文脈で名前・用語・トーンを整える」とだけ説明 | 見つからなかった | アプリごとのプリセット、ショートカット（定型句） | 言及なし（100 以上の言語とだけ説明） |
| VoiceInk（ソース） | 17 個のメールアプリのバンドル ID と 11 個のサイト | Email プロンプト（挨拶・箇条書き・結びを声のとおりに整える） | 選択テキスト、クリップボード、画面の OCR を AI に渡す | Rewrite、Assistant の各モード | モードごとの設定、トリガーワード、プロンプトの編集 | 日本語メール専用の処理は見つからなかった |
| MacWhisper | アプリごとのプロンプト（実行中のアプリを選んで追加） | 専用の整形はなく、ユーザーのプロンプトに任せる | 見つからなかった | AI プロンプトを話した文に適用 | アプリごとのプロンプト、独自プロンプト | 見つからなかった |
| OpenWhispr（ソース、補足） | アプリ名とバンドル ID、ブラウザは URL のホスト、なければウィンドウタイトルの末尾 | トーンを Email カテゴリで選ぶ。挨拶・結びは話したものだけ残す | 音声アシスタントが画面のスクリーンショットを使える（既定オフ） | 音声アシスタント（選択範囲の編集、メール下書きツール） | カテゴリごとのトーン、プロンプト編集 | トーン指示は英語。日本語向けの敬語処理は見つからなかった |
| Amical（ソース、補足） | バンドル ID と、ブラウザの URL の正規表現 | Email 用のルールと例（挨拶・本文・結びを空行で分ける） | 見つからなかった（カーソル前後のテキストは渡す） | 「instruct」プリセット（話した指示から生成する） | Email などのトーン（Formal/Excited/Casual） | 日本語向けの処理は見つからなかった |
| Handy（ソース、補足） | 見つからなかった | メール向けの処理なし | なし | なし | 後処理プロンプトを自分で書く（既定は 1 つ） | なし |
| Monologue（補足） | アプリ/サイトを指定して自動切り替え | Email モード（断片から完全な文を作る） | 「画面の文脈」を準備すると変更履歴にある | モードの切り替え | カスタム指示、モードの割り当て | 見つからなかった |
| Spokenly（補足） | App Focus（公式サイトの比較ページによる） | モードにメール用の指示を書く | 画面は読まない（同上） | 見つからなかった | モード、アプリごとの設定 | 見つからなかった |

## 3. アプリごとの詳細

### 3.1 Typeless

#### (1) メールの見分け方
- アプリに合わせてトーンを変えると説明している。「Different tones for each app」の見出しで、仕事のメールから雑談まで調整するとある（確認）。https://www.typeless.com
- 見分け方（バンドル ID、URL、ウィンドウタイトル）は書かれていない。データ管理のページは「使っているアプリ」と「その中の関連するテキスト」を処理に送る、と述べている。ウィンドウタイトルやスクリーンショットには触れていない（確認）。https://www.typeless.com/data-controls

#### (2) 整形・(5) 設定
- 個人化: 「使うほどトーンに合ってくる」「設定は不要」。オフにすると学習をやめる。設定の場所は Settings > Personalization（確認）。https://www.typeless.com/help/release-notes/macos/personalized-smarter （macOS v0.9.0、2025-12-24）
- Gmail と Outlook のユースケースが載っている。「話した考えを、あなたらしいメールに」という趣旨の説明だけで、挨拶・署名の自動補完の記述はない（確認）。https://www.typeless.com/use-cases
- アプリごとに自分で規則を書く機能は、見つからなかった（探した場所: /help、/help/faqs、/help/release-notes、/help/release-notes/macos、ホームページ）。

#### (3)(4) 返信の文脈・コマンド
- Ask Anything: 選択したテキストに対して声で命令する。書き換え（「もっと温かく」）、要約、翻訳、下書き（「〜のフォローアップメールを書いて」）。下書きは入力中の欄に出る。メールの例として「送る前に厳しい文面のトーンを変える」がある（確認）。https://www.typeless.com/ask-anything
- 画面の受信メールを読んで返信を書く機能は、見つからなかった（推測: 選択範囲だけを読む）。

#### (6) 日本語
- 100 以上の言語に対応し、自動検出すると説明するだけ。日本語の敬語・定型挨拶の記述は見つからなかった（確認）。https://www.typeless.com

### 3.2 Wispr Flow

#### (1) メールの見分け方
- アプリの種類から Email カテゴリを決める。Mac・Windows・Android では、Web アプリを URL でも見分ける。Missive のデスクトップ版とブラウザ版も Email に入る（確認）。https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles
- 見分ける仕組みの詳細（バンドル ID の一覧など）は書かれていない。
- iOS では 2026-03-31（v1.46）に「Styles がアプリで自動的に切り替わらなくなった」とある（確認）。https://wisprflow.ai/whats-new

#### (2) 整形・(5) 設定
- Styles: カテゴリ（Personal、Work、Email、Other）ごとにトーンを選ぶ。Email は Formal、Casual、Excited。既定は Formal。Very casual は Personal のみ（確認）。同上の Styles 記事。
- 「メールのアプリでは、選んだ Email の Style と、メール向けの整形（挨拶、結び、改行）が適用される」（確認）。https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack
- 「新しい段落」「改行」の音声コマンドがある（確認、同上）。
- スニペット: 「my email signature」のような合図の言葉で、保存した署名・住所・定型文を挿入する。複数行、箇条書き、リンクも保存できる。デスクトップでは日付などの変数は使えない（確認）。https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets
- Outlook の記事は、本文や件名欄で使う手順を説明するだけ。宛名・署名の扱いは書かれていない（確認）。https://docs.wisprflow.ai/articles/9272331366-use-flow-with-microsoft-outlook
- 自動クリーンアップ（Beta）: None/Light/Medium の 3 段階。メール専用の設定はない（確認）。https://docs.wisprflow.ai/articles/4283510616-auto-cleanup-control-how-much-flow-edits-your-dictation-beta

#### (3) 返信の文脈
- 「Flow は周囲の文脈を使って、珍しい名前の綴りを当てる」（確認）。https://wisprflow.ai/features
- Android の権限説明に、入力欄の近くに見えるテキストを読むこと、宛先の名前を綴るのに役立つこと、設定で止められること、銀行アプリなどの機密欄は除外されることが書かれている（取得ツールの要約による。ページを直接は取得できず、検索結果の要約で確認した。デスクトップ版の同等のページは見つからなかった）。https://docs.wisprflow.ai/articles/7669452251-accessibility-permission-on-android
- 変更履歴: Android v1.4.1（2026-03-31）に「入力欄の周りのテキストを読んでから書き起こす」（確認）。https://wisprflow.ai/whats-new

#### (4) コマンド型
- Command Mode: 「テキストを編集する、返信を下書きする、検索する」。入力欄の内容と選択範囲を送る。既定はオフ（Settings → Experimental）。ホットキーはどの言語でも使えるが、話し言葉のトリガーは英語のみ。メールの例は書かれていない（確認）。https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode
- Transforms（2026-05-01 の告知）: 選択した文を、ショートカットで書き換える。Polish、Prompt Engineer のほか、自分のプロンプトを最大 8 個。文体の見本（50〜500 語）を最大 5 つ付けられる。話した後に自動で適用する設定もある。元の文との差分を見る機能もある。入力欄の内容、または直近 60 秒の発話を対象にする（確認）。https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta
- 後から戻せる: 「Undo AI edit」で元の書き起こしに戻る（確認）。Smart Formatting の記事。

#### (6) 日本語
- Styles は英語のみ（確認）。Styles の記事、https://wisprflow.ai/features の「英語とデスクトップのみ」の注記。
- 100 以上の言語で書き起こせる（確認）。日本語の敬語や定型挨拶の記述は見つからなかった。

### 3.3 Superwhisper

#### (1) メールの見分け方
- モードごとに「Activate for apps」で、アプリとサイトを指定する（確認）。https://superwhisper.com/docs/modes/modes.md
- 判定方法（バンドル ID か名前か）は書かれていない。

#### (2) 整形
- Mail モード: 「適切な挨拶、段落分け、結びを足す。あなたの自然な口調を保つ。文法と句読点を直す」。トーンのスライダー（Casual〜Formal）がある（確認）。https://superwhisper.com/docs/modes/built-in.md
- ローカルモデルの S1-mini は Message と Mail のモードで使える（確認、同上）。

#### (3) 返信の文脈
- Super モードは、アクセシビリティ API で 3 種類の文脈を集める。アプリ（有効なアプリの名前と、現在の入力欄やエディタのテキスト）、選択テキスト、クリップボード（録音の 3 秒前から録音中までにコピーした文）。アプリの文脈が有効なときは、日付・時刻・利用者の氏名・コンピュータ名も渡し、「メールの結びに名前を入れる」などに使えると書いている（確認）。同上。
- 文脈の取得は、Custom モードで 3 種を個別に選べる（Pro）。取り込みすぎは品質を下げるので、必要なものだけ選ぶよう勧めている（確認）。https://superwhisper.com/docs/modes/custom.md 、https://superwhisper.com/docs/common-issues/context.md
- 受信メールの本文を読んで返信を書く専用の機能は、見つからなかった。ただし Custom モードの指示で「Application Context を踏まえて」と書けるため、設定次第で可能と思われる（推測）。

#### (4) コマンド型
- Super モードのコマンドは書式変換向け。「Make this text title case」は向くが、「Summarize」「Expand」「Rewrite」は向かないと明記している（確認）。同上。

#### (5) 設定
- Custom モードの自由な指示、文脈の 3 種の選択、アプリ/サイトの自動切り替え、ディープリンク（確認）。https://superwhisper.com/docs/modes/switching-modes.md

#### (6) 日本語
- 日本語メールや敬語の記述は見つからなかった（探した場所: modes/built-in、modes/custom、models/language、llms.txt）。100 以上の言語に対応するとだけある。

### 3.4 Aqua Voice

#### (1) メールの見分け方
- 「どのアプリでも追加設定なしで動く」。Gmail、Apple Mail、Outlook を対象アプリに挙げ、「そのまま送れるメールを話す」とある（確認）。https://aquavoice.com
- 見分け方の詳細は書かれていない。

#### (2) 整形・(5) 設定
- カスタム指示（Pro）: 「メールの冒頭と署名の改行」を指定できる例がある。「メールの結びの書き方を覚える」とある。「Never use em-dashes」などの規則も書ける。アプリごとの設定は書かれていない（確認）。https://aquavoice.com/guide/custom-intructions （URL の綴りは原文のまま）

#### (3) 返信の文脈
- Deep Context: 開始時に画面全体のスクリーンショットを 1 枚撮り、話している間に読んで、画面上の名前・用語・コードの綴りを合わせる。「開いている受信箱は、書いているメールと同じくらい重要」と説明している。録音はしない。スクリーンショットは文字を抜いた後に捨てる。既定はオフ。macOS と Windows のみ。メールの具体的な出力例は載っていない（確認）。https://aquavoice.com/deep-context

#### (4) コマンド型
- Edit Mode（2026-07-20 に告知）: 選択して Space を押したまま、変更を話す。例は「Change Thursday to Friday」「Make it more formal」「Translate to Japanese」。Gmail が対象アプリに入っている。選択が 6,000 文字を超えると編集せず口述になる（確認）。https://aquavoice.com/edit-mode 、https://aquavoice.com/changelog

#### (6) 日本語
- 2026-10-06「Japanese 認識の誤りが 33% 減った」。2026-07-26「Send It」コマンドが英語・日本語など 6 言語の言い回しに対応（確認）。https://aquavoice.com/changelog
- 敬語・定型挨拶の処理は見つからなかった。

### 3.5 Willow Voice

#### (1)(5) 見分け方・設定
- アプリごとにスタイルを選ぶ。Email（Gmail、Outlook、Apple Mail）は Default、Casual Friendly、Excited の 3 つ。Casual Messaging、Work Messaging、Note-Taking も同様（確認）。https://help.willowvoice.com/en/articles/12864746-personalization-and-style-matching
- アプリの見分け方、言語、カスタム指示は、この記事に書かれていない（確認）。
- 「ショートカット」: よく使う語句を保存して、短い指示で挿入する（確認）。https://willowvoice.com/features/dictation

#### (2) 整形
- 「挨拶、本文、結びを分け、改行を入れる」。例は、独立した挨拶の行、本文、結びの語と送り主の名の順（確認）。https://help.willowvoice.com/en/articles/13183983-voice-commands-and-automatic-formatting-guide

#### (3)(4)(6)
- 「名前、用語、トーン、書式を文脈で整える」とだけ書かれ、読み取る対象は説明がない（確認）。返信用のコマンドは見つからなかった。日本語は「100 以上の言語」とだけある。

### 3.6 VoiceInk（ソース）

#### (1) メールの見分け方
- トリガーのカタログに「email」がある。バンドル ID 17 個（Mail、Outlook、Mimestream、Spark、Canary、eM Client、Proton Mail、Spike、MailMate、Airmail、Thunderbird、Mailspring、Superhuman、Missive、Edison、Polymail）と、サイト 11 個（mail.google.com、outlook.live.com、outlook.office.com、icloud.com/mail、mail.proton.me、app.superhuman.com、app.shortwave.com、hey.com、fastmail.com、missiveapp.com ほか）（確認）。`VoiceInk/Features/Modes/Templates/TriggerTemplateCatalog.swift` L109-L136
- ブラウザの URL の取得は `Infrastructure/SystemIntegration/Context/BrowserURLService.swift` が担う（ファイル名の確認まで。中身は読んでいない）。

#### (2) 整形
- Email プロンプトは「文字起こしを、読みやすい整ったメールにする」。例は、挨拶、本文、番号付きの箇条書き、結び（"Thanks, Alex"）。例の挨拶と結びは、入力で話されたもの（確認）。`VoiceInk/Features/Enhancement/Templates/PromptTemplates.swift` L80-L107
- 全モードに共通のシステム指示: 話し手の意味・口調・丁寧さを保つ。「formalize しない」。言い直しを整理する。段落は 3 文または約 40 語まで。話していない情報は足さない（確認）。`VoiceInk/Core/Enhancement/AIPrompts.swift` L1-L30

#### (3) 返信の文脈
- Email モードは、選択テキスト、クリップボード、画面の文字（OCR）を使う設定で作られる（`useClipboardContext: template.kind == .email`、`useSelectedTextContext`、`useScreenCapture`）。画面の文字は `VNRecognizeTextRequest` で読む（確認）。`StarterModeTemplate.swift` L80-L95、`StarterModeFactory.swift` L87、`Infrastructure/SystemIntegration/ScreenCapture/ScreenCaptureService.swift` L211
- 文脈は `<CURRENTLY_SELECTED_TEXT>`、`<CLIPBOARD_CONTEXT>`、`<CURRENT_WINDOW_CONTEXT>` として渡す。システム指示は「文脈から話していない情報を写さない。文脈は綴りと用語の補正に使う」と限定している（確認）。`Features/Enhancement/Workflows/AIEnhancementService.swift` L127-L147、`AIPrompts.swift` L22-L28。

#### (4) コマンド型・(5) 設定
- Rewrite モード: 選択テキストを元にして、話した内容を書き換えの指示として使う（確認）。`PromptTemplates.swift` L109 付近。
- モードごとにトリガー（アプリ/サイト）、プロンプト、AI の設定を持つ。トリガーワードで切り替えるサービスもある（`ModeTriggerWordDetectionService.swift`）（確認）。

#### (6) 日本語
- 敬語・定型挨拶の処理は見つからなかった（探した場所: Prompts、Templates、Localizable）。

### 3.7 MacWhisper

- 「アプリごとのプロンプト」: 設定の Dictation タブで、実行中のアプリを選び、自分のプロンプトを割り当てる。メールの例として「仕事のメールでは、綴りが正しく、プロらしく読めること」を挙げている（確認）。https://docs.macwhisper.com/article/31-app-specific-dictation-prompts
- 「くだけた話し方を、カスタマーサポートのメールに広げる」例もある（確認）。https://docs.macwhisper.com/article/14-how-to-use-the-dictation-feature
- アプリの見分け方、文脈（選択範囲・クリップボード）、日本語の記述は見つからなかった。この 2 つの記事は古い可能性がある（検索結果のページの更新日が約 600 日前）。

### 3.8 OpenWhispr（ソース、補足）

#### (1) メールの見分け方
- macOS はアプリ名とバンドル ID のトークン、Windows は exe 名とウィンドウクラス。ブラウザは、アクセシビリティで取れた URL のホストを優先し、取れなければウィンドウタイトル末尾のサイト名（"Inbox (3) - me@gmail.com - Gmail - Google Chrome" の "Gmail"）で判定する（確認）。`src/helpers/toneAppCategories.js` L1-L30、L146-L160
- 取得方法: `macos-text-monitor --app-context <pid>` がアプリ名、バンドル ID、ウィンドウタイトル、ブラウザの URL ホストを出す。画面収録の許可は不要（確認）。`CLAUDE.md` L801

#### (2) 整形
- カテゴリは personal、work、email、other。トーンは email が formal/casual/excited、既定 formal。Tone & Style は既定オフ（確認）。`src/config/toneStyle.ts` L5-L25、`CLAUDE.md` L795-L801
- メールの指示: 「メールである。話した挨拶、段落、結びはそれぞれ独立した行に保ち、話していない挨拶と結びは足さない」（確認）。`src/config/prompts/toneStyle.ts` L32-L34
- トーンの文は英語で書かれ、「どのロケールでも英語」とコメントがある。日本語でどう効くかは未確認（確認:英語であること。推測:日本語の敬語は扱わない）。`src/config/prompts/toneStyle.ts` L1-L25

#### (3) 返信の文脈
- 音声アシスタントは「Share screen context」を有効にすると、録音開始時にカーソルのある画面のスクリーンショットを付ける。既定はオフ（確認）。`CLAUDE.md` L762
- オンボーディングのデモは、メールのスレッドに返信する例（確認）。`CLAUDE.md` L757

#### (4) コマンド型
- 選択範囲は音声アシスタントで書き換えられる。選択がないと、チャットとして答える（確認）。`CLAUDE.md` L738、L740
- `email_draft` ツール: 宛先、件名、本文を作る。Gmail を連携していれば編集可能なカードを出し、送信まで行う。連携がなければ Gmail、Outlook、mailto の作成画面を開く（確認）。`src/services/tools/connectors/emailDraftTool.ts` L36-L50、`CLAUDE.md` L190-L191
- 署名: アカウント名があれば、メールの署名にその名前を使う。なければ、署名行を書かない。「[Your Name]」のようなプレースホルダーは残さない（確認）。`src/config/prompts.ts` L127-L152

#### (6) 日本語
- 日本語向けの敬語・定型挨拶の処理は見つからなかった（探した場所: src/config、src/locales/prompts.ts。検索語: keigo、敬語、polite）。UI は日本語に翻訳されている。

### 3.9 Amical（ソース、補足）

#### (1) メールの見分け方
- バンドル ID の表（`com.apple.mail`、`com.microsoft.Outlook`、`com.readdle.smartemail`、`com.google.Gmail`、`com.superhuman.electron` ほか）と、ブラウザの URL の正規表現（`mail.google.com`、`outlook.live.com`、`outlook.office.com`、`mail.yahoo.com`、`mail.proton.me`、`webmail.`、`roundcube`、`fastmail.com`）（確認）。`apps/desktop/src/pipeline/providers/formatting/formatter-prompt.ts` L301-L306、L333-L341、L378-L440
- クラウド側のプリセット決定は `shared/app-catalog.ts` のカタログ（Apple Mail、Spark、Airmail、MailMate、Proton ほか）を使う（確認）。`pipeline/providers/transcription/skill-resolution.ts` L60-L80

#### (2) 整形
- Email ルール: 挨拶・本文・結びを空行で分ける。業務向けの丁寧さを保つ。「Hi」と「Dear」のような、話し手の丁寧さの度合いを保つ。例に「話した挨拶と結びだけ」と「挨拶を足さない」ものがある（確認）。同ファイル L20-L24、L52-L70
- トーンのプリセット（Email、Work messages、Personal messages、Default）と Formal/Excited/Casual。ただしコードの `PERSONALIZATION_OFF = true` により、現状はトーンを送らない（確認）。`skill-resolution.ts` L19、`renderer/main/pages/settings/formatting/catalog.ts` L8-L58

#### (3)(4)(6)
- 返信の文脈: カーソルの前後のテキストを渡す。受信メールの読み取りは見つからなかった。
- 「instruct」プリセットは、話した指示から生成するモード（確認）。ユーザー定義のスキルは「近日公開」と画面に書かれている（`settings/formatting/index.tsx` L113-L114）。
- 日本語向けの処理は見つからなかった。

### 3.10 Handy（ソース、補足）

- 「後処理」のプロンプトを自分で書く。既定は「Improve Transcriptions」の 1 つで、綴り・句読点・数字・フィラー除去だけを行う（確認）。`src-tauri/src/settings.rs` L807-L813
- アプリの見分けやメール向けの処理は見つからなかった（検索語: email、gmail、outlook、signature、greeting、bundle、frontmost。`src-tauri/src` と README）。

### 3.11 そのほかのアプリ

- Monologue: Mac ではモードをアプリやサイトに自動で割り当てられる。Email モードは「断片から完全なメッセージを作る」例（確認）。https://www.monologue.to/docs/personalize/modes-and-instructions 。変更履歴に「長い発話では、画面の文脈とモードの指示を話し終わる前に準備する」（2026-09-28）、「テキストの文脈をブラウザで拡大」（2026-03-06）とある（確認）。https://www.monologue.to/changelog 。画面の文脈の詳細と日本語は見つからなかった。
- Spokenly: 公式サイトの検索結果の要約から、App Focus（アプリごとにモードを自動切り替え）を挙げている。ただし該当ページを直接読めておらず、`/docs/support` にはモードの説明がなかった。確認できていない。
- Apple: Mail の Apple Intelligence に Smart Reply（返信の候補を選ぶ）と Writing Tools（校正、書き直し、トーン調整）がある（確認）。https://support.apple.com/guide/mac-help/use-apple-intelligence-in-mail-mchlb2dbea8f/15.0/mac/15.0 。macOS のディクテーション自体のメール向け機能は、見つからなかった。
- Gmail の Help me write: 作成画面で指示を入力すると下書きが出る。Refine に Polish、Formalize、Elaborate、Shorten がある（確認、古いページ）。https://support.google.com/mail/answer/13384326 。音声入力については書かれていない。
- Voibe: 公式ページを調べていない。

## 4. Koebumi への示唆

Koebumi の現状（比較のため、コードで確認した範囲）。メールはバンドル ID とウィンドウタイトルで分類する。既定は丁寧で、日本語は です/ます。話していない挨拶・署名は足さない。画面の人名・用語を AI に渡し、宛名の表記を合わせる。「選択テキストの書き換えや質問」のコマンド型モードがある（`UI/HomeView.swift` L38）。署名やスニペットの登録機能は、見つからなかった。

効果が大きそうな順に並べる。

### 4.1 署名・定型挨拶の登録と、合図の言葉による挿入
- 競合の機能: Wispr Flow のスニペット（「my email signature」と言うと署名が入る。複数行、箇条書きも可）。Aqua Voice のカスタム指示（結びの書き方を覚える）。Superwhisper（氏名を AI に渡し、結びに使う）。OpenWhispr（アカウント名で署名し、名前がなければ署名行を書かない）。
- 出典: https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets 、https://aquavoice.com/guide/custom-intructions 、https://superwhisper.com/docs/modes/built-in.md 、`src/config/prompts.ts` L127-L152（OpenWhispr）。
- 日本語メールの観点: 日本語の署名は、氏名、所属、連絡先の複数行の定型で、毎回同じになる。「署名」と話したら、登録済みの本文をそのまま挿入する形が合う。AI が書き換えない点は、Koebumi の「話していない署名は足さない」方針と矛盾しない（話したのは合図だけ、という扱い）。
- 推測: 登録文は AI に通さず、整形後に差し込む方が、署名の文字が崩れない。

### 4.2 返信モード: 画面の受信メールから、相手の呼称・敬語の高さ・宛名の敬称を拾う
- 競合の機能: Superwhisper の Super/Custom モード（入力欄のテキストと選択範囲を渡す）。VoiceInk の Email モード（選択テキスト、クリップボード、画面の OCR）。Aqua Voice の Deep Context（受信箱の画面から名前を拾う）。
- 出典: https://superwhisper.com/docs/modes/built-in.md 、`StarterModeFactory.swift` L87 と `ScreenCaptureService.swift` L211（VoiceInk）、https://aquavoice.com/deep-context 。
- 日本語メールの観点: 競合は主に綴りの補正に使う（VoiceInk は文脈から話していない情報を写さないと指示している）。Koebumi は人名・用語の一覧だけを渡しているので、さらに「宛名に付ける敬称（様、さん、各位）」と「相手が使っている敬語の高さ」を、画面の文面から選ぶ方向が考えられる。社外か社内かで、「お世話になっております」と「お疲れ様です」の使い分けが変わる。
- 推測: 受信メール全文を AI に渡さず、敬称と宛名だけを抜き出す設計にすれば、現在のプライバシーの方針を保てる。

### 4.3 話した要点から本文を下書きするコマンド（明示的に頼んだときだけ）
- 競合の機能: Wispr Flow の Command Mode（「返信を下書きする」）。Typeless の Ask Anything（「〜のフォローアップメールを書いて」、下書きは入力中の欄に出る）。OpenWhispr の `email_draft`。Monologue の Email モード（断片から完全な文）。
- 出典: https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode 、https://www.typeless.com/ask-anything 、`emailDraftTool.ts`（OpenWhispr）、https://www.monologue.to/docs/personalize/modes-and-instructions 。
- 日本語メールの観点: 「来週の打ち合わせの日程を断る」のような要点だけから、日本語の定型（冒頭の挨拶、お詫び、結び）を含む下書きを作る。Koebumi の Ask anything には、選択がなく入力欄にカーソルがあるとき、頼まれた文を書いて入力する動き（Insert）がすでにある（`AI/Prompts.swift` の `askSystemCommon`。例として「返信やメールの下書き」を挙げている）。足りないのは、日本語メールの型（冒頭の挨拶、お詫び、結び）と、画面の受信メールの宛名を下書きに反映する部分。
- 注意: 通常のディクテーションは「足さない」を保つ。下書き生成は、頼んだときだけにする。Superwhisper は、Super モードのコマンドは書式変換向けで、生成・書き換えは向かないとしている。

### 4.4 メールアプリ・Webメールの判定を広げ、ユーザーが追加できるようにする
- 競合の機能: VoiceInk はバンドル ID 17 個とサイト 11 個を持つ。OpenWhispr はウィンドウタイトル末尾のサイト名でも判定する。Amical は `webmail.`、`roundcube` のような汎用パターンを使う。Superwhisper と MacWhisper と Monologue は、ユーザーがアプリやサイトを割り当てる。
- 出典: `TriggerTemplateCatalog.swift` L109-L136（VoiceInk）、`toneAppCategories.js` L1-L30、L146-L160（OpenWhispr）、`formatter-prompt.ts` L333-L341（Amical）、https://superwhisper.com/docs/modes/modes.md 、https://docs.macwhisper.com/article/31-app-specific-dictation-prompts 。
- 日本語メールの観点: 日本の職場は Outlook（Web 版を含む）、Gmail、各社のウェブメールが多い。タイトルが日本語の画面（Outlook の受信トレイなど）でも判定できるか、確認する価値がある。
- Koebumi の現状（確認）: スタイル画面の「アプリの種類」で、アプリ（バンドル ID）ごとに種類を上書きできる（`Core/Settings.swift` の `appCategoryOverrides`、`UI/StyleView.swift`）。ブラウザの中のサイトごとには上書きできない。
- 推測: Koebumi のバンドル ID の一覧に、Thunderbird、Canary、eM Client、MailMate、Missive、Spike、Polymail がない。ウィンドウタイトルの一覧に、iCloud メール、Fastmail、Zoho がない。

### 4.5 整形のやり直し（元の文に戻す、差分を見る）
- 競合の機能: Wispr Flow の「Undo AI edit / Redo AI edit」と Transforms の View Diff。
- 出典: https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack 、https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta 。
- 日本語メールの観点: です/ます化や敬語化は、AI が意図と違う丁寧さにすることがある（Koebumi の `Polisher.swift` には くだけた口調の保持を確認する処理がある）。送信前に、元の発話と見比べて戻せると安心。Koebumi の履歴には再処理があるが、入力した直後にその場で元に戻す操作はない（確認: `docs/features.md` の履歴の行）。

### 4.6 文体の見本を渡して、自分の書き方に寄せる
- 競合の機能: Wispr Flow の Transforms（文体の見本を最大 5 つ、各 50〜500 語）。Typeless の個人化（使うほどトーンが合う）。Willow Voice のスタイル合わせ。
- 出典: https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta 、https://www.typeless.com/help/release-notes/macos/personalized-smarter 、https://willowvoice.com/features/dictation 。
- 日本語メールの観点: 敬語の程度、文末の癖（「〜と存じます」と「〜と思います」）、結びの言葉は人ごとに違う。過去に送ったメールを見本にして、書き方を合わせられる。Koebumi には、6 回話すごとにアプリの種類ごとの文体（丁寧さ・詳しさ・癖）を学ぶパーソナライズがある（`Data/PersonalizationStore.swift`）。足りないのは、ユーザーが見本の文を直接渡す手段。

## 5. わからなかったこと

- Typeless、Aqua Voice、Willow Voice のアプリの見分け方（バンドル ID、URL、タイトルのどれか）。公式ページに書かれていない。これらは非公開のため、ソースを読めない。
- Wispr Flow のデスクトップ版が、入力欄の周りのテキストをどこまで読むか。Android 版の権限説明は読めたが、macOS 版の同等の公式ページは見つからなかった。
- Superwhisper の自動切り替えルールが、アプリをバンドル ID で見るかどうか。サイトを URL とタイトルのどちらで見るかも同様。
- Willow Voice の「名前を拾って挨拶を整える」の詳細。検索結果の要約にあったが、取得した記事の本文では確認できなかった。
- Spokenly、Voibe、OpenWhispr 以外の Amical の「instruct」プリセットのクラウド側の仕様。Spokenly は該当ページを読めなかった。Voibe は調べていない。Monologue の Email モードの出力例も未確認。
- 日本語のメール（敬語、「お世話になっております」などの定型）に特化した処理は、調べた範囲の競合のどれにも見つからなかった。日本語での挙動は、モデル任せかどうかを、実機で試さないと判断できない。
- Apple のディクテーションのメール向けの機能。Mail の Apple Intelligence は見つかったが、ディクテーションとの関係は書かれていない。Gmail の Help me write の音声入力も、公式ページに記述が見つからなかった。
- Koebumi 側の「カテゴリごとのトーン設定」と「ユーザー定義のアプリ規則」の有無は、`Models.swift` の分類（email、chat、document、code、ai、other）を見た範囲の確認で、設定画面は細かく読んでいない。4.4 の提案は、その前提。
