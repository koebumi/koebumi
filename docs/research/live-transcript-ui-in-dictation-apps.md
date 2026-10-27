# 音声入力アプリが録音中に途中の書き起こしをどう見せているか

調査日: 2026-10-26。一次情報だけを根拠にした。一次情報とは、各社の公式サイト・ヘルプセンター・公式ドキュメント・変更履歴・公式ブログ、オープンソースのソース、Apple・Microsoft・Google のサポートページと開発者ドキュメントを指す。第三者のレビュー記事・まとめ記事・SNS は根拠にしていない。検索結果に出た第三者の記事は、一次情報の場所を探す手がかりにだけ使った。使った箇所には「二次」と書いた。

各主張に「確認」か「推測」を付けた。
- 確認: 一次情報の該当箇所を読んで確かめた。
- 推測: 読んだ内容からの推論で、直接は確かめていない。

Web のページの多くは、取得ツールが本文を要約して返す方式で読んだ（生の HTML は読んでいない）。そのため、引用の言い回しが原文と少し違う可能性がある。Apple のサポートページと開発者ドキュメント、Microsoft の音声入力のページと開発者ガイド、Android のリファレンス、Spokenly のドキュメント（llms-full.txt）は、本文をそのまま取得して読んだ。これらの引用は原文どおり。ソースを読んだものは、ファイルと行を付けた。

読んだコミットは次のとおり。すべて shallow clone で、クローンの中のコードは実行もビルドもしていない。

| 対象 | SHA |
|---|---|
| VoiceInk | `78aa19ddb5c8b2f378ac650184491c1f26c230f7` |
| OpenWhispr | `f2a269646075ab4a82b86f08802aeaf315191520` |
| Handy | `73c095857bc4eadff097f64767c40ad129cc372d` |
| Amical | `d5604ef548816d8729b1170696d315a35c00391a` |
| epicenter（Whispering を含む） | `7cc869b4a1295e2566b61e1a4d5967a89f413b9b` |
| Koebumi（比較用、このリポジトリ） | `13b8aa8aed08b827023e6c487a7ca486d6bee2b6` |

Apple の公式サンプル「Bringing advanced speech-to-text capabilities to your app」は、配布されている zip を取得してソースだけを読んだ（ビルドしていない）。

前回までの調査メモ（メール、マイク）とは、VoiceInk・OpenWhispr・Handy・Amical の SHA が違う。今回あらためて clone したため。

## 1. 要約

- 録音中に途中の文字を出すかどうかで、アプリは 2 つに分かれる。出すのは VoiceInk、OpenWhispr、Handy、Superwhisper、Aqua Voice、Spokenly（一部のモデル）と、OS 標準のディクテーション（Apple、Windows、Google）。公式資料の範囲で出さないのは Wispr Flow、Typeless、Willow Voice、Amical、MacWhisper、Whispering。出さないアプリは、話し終えてから整えた文を入力欄に入れる。
- 出す場所も 2 つに分かれる。他社のアプリは、すべて自分の録音バーやパネルの中に出す（VoiceInk と Handy はバー自体が上に広がる。OpenWhispr はフローティングパネル。Superwhisper は録音ウィンドウ。Aqua Voice はツールバー）。OS 標準のディクテーションは、入力欄に直接文字を入れる。入力欄のカーソル位置に薄い文字を「重ねる」作り（Koebumi の C 案）は、調べた範囲では見つからなかった。字幕のような見せ方（D 案）は、ライブキャプションだけだった。
- まだ確定していない文字を見た目で区別するアプリは少ない。Handy は確定部分（committed）と未確定部分（tentative）を分けて持つが、色は同じにしている。OpenWhispr は末尾の 6 語を光らせる（日本語はスペースがないので、全体が光ると読める。推測）。VoiceInk は区別しない。区別の手本になるのは開発者向けの資料で、Apple の公式サンプルは確定前の文字を薄い紫（不透明度 0.4）で出す。Microsoft のガイドは、途中の仮説の後ろに「...」を付けて出し、確定したら置き換えると書いている。
- 録音中に AI 整形の前後の差分を見せるアプリは、見つからなかった。差分や元に戻す操作は、入力した後にある（Wispr Flow の Undo AI edit と Transforms の View Diff、Aqua Voice の履歴の Undo、Windows の Fluid dictation の「Revert」）。入力前に確かめる画面は、Amical の Draft（話した指示から文を生成するモードだけ）にあった。差分は出さない。
- 途中の文字の表示をオン・オフする設定は、出すアプリのほとんどにある。VoiceInk（Live Text Display、既定オン）、OpenWhispr（Live Transcription Preview、既定オフ）、Handy（Overlay を None・Minimal・Live から選ぶ。macOS の既定は Live）、Superwhisper（モードごとの Realtime）、Aqua Voice（Realtime always と Instant always）。Koebumi には今この設定がない。

## 2. 比較表

| | (1) 途中の文字と場所 | (2) 未確定の文字の見せ方 | (3) 整形の前後・戻す・入力前の確認 | (4) 言い直し | (5) オン・オフ |
|---|---|---|---|---|---|
| VoiceInk（ソース） | 出す。録音バーが横に 184 から 300 に伸び、操作の列の上に高さ 56 の欄を開く。ノッチ型は下に開く。録音中だけ。対応モデルのみ | 区別しない（全体を 12pt、白の 80%）。確定した区間と途中の文を空白でつなぐ | 欄に整形後の文は出さない。差分と入力前の確認は見つからなかった | 見つからなかった | Live Text Display（既定オン）。モードごとの Real-time |
| OpenWhispr（ソース） | 出す（既定オフ）。フローティングパネルに全文。ローカルモデルと BYOK のストリーミングのみ | 末尾 6 語を光らせる（シマー）。整形中も光らせる | 話し終えると最終の文に置き換え、4 秒残す（ホバー中は残す）。コピーと折りたたみ。差分なし | 見つからなかった | Live Transcription Preview（既定オフ） |
| Handy（ソース） | 出す。小さなピルが上に開いてパネルになる。ストリーミング対応モデルのみ | committed と tentative を分けて受け取るが、色は同じ。全体を斜体で、末尾に点滅するカーソル | 整形中は文を残したままスピナーと「処理中」を出す。整形後の文はパネルに出さない（推測） | 見つからなかった | Overlay: None / Minimal / Live（Linux 以外の既定は Live） |
| Amical（ソース） | 出さない | 該当なし | Draft モードだけ、生成した文をパネルで見せ、Insert（Enter）・Copy・閉じる（esc）を選ぶ。差分なし | 該当なし | Draft は通常と別のショートカット |
| Whispering（ソース） | 出さない。他のアプリへのディクテーション自体がない | 該当なし | 該当なし | 該当なし | 該当なし |
| Superwhisper | 出す。録音ウィンドウ。Realtime 対応モデルのみ（Pro） | 記述なし | 履歴に音声・書き起こし・AI の結果を残し、別のモードで再処理できる。自動貼り付けを切ると、クリップボードに入れるだけになる | 記述なし | モードごとの Realtime。録音ウィンドウを None にできる |
| Aqua Voice | 出す（Realtime Mode）。ツールバー。話し終えるとアプリに入れる | 「a beat behind you」整った文に変わる。区別の記述なし | 履歴の Undo で元の書き起こしに戻す。Paste Only（入力するが送信しない） | 「change Thursday to Friday」と言うと、送る前にライブの文が直る | Realtime always / Instant always（Max と Business） |
| Wispr Flow | 公式資料の範囲で出さない。Flow Bar は待機・録音・処理の状態だけ | 該当なし | Undo AI edit（履歴から）。Transforms は Flow Bar の「See changes」で差分を開き、Undo できる | Backtrack は最終の文に反映 | Flow Bar の常時表示のオン・オフ |
| Typeless | 記述なし。話し終えると入力 | 該当なし | 記述なし | 言い直しは最終の文にだけ反映 | 記述なし |
| Willow Voice | 記述なし。キーを離すと入力 | 該当なし | 記述なし | 「No wait, actually, 5 p.m.」の例。最終の文に反映 | バーを消す設定（Notch View） |
| Spokenly | ストリーミング対応モデルで出す。場所は記述なし | 記述なし | 記述なし | 記述なし | プロバイダごとのストリーミング設定 |
| Monologue | iOS は Real-time が既定。Mac の Dot は入力欄の横に状態を出す。文字を出すかは記述なし | 記述なし | 記述なし | 記述なし | Indicator: Classic / Mini / None |
| MacWhisper | ディクテーション中の表示は記述なし | 該当なし | AI プロンプトを適用。差分は記述なし | 該当なし | 該当なし |
| macOS のディクテーション | 入力欄に直接入れる。改行は話し終えてから入るとある | 話し終えた後、あいまいな語に青い下線。クリックで別の候補を選ぶ | AI 整形はない（自動句読点のみ） | キーボードで直せる（Apple シリコン） | 自動句読点のオン・オフ |
| iOS のディクテーション | 入力欄に直接入れる。キーボードは開いたまま | 記述なし | iOS 27 の Apple Intelligence で綴り・句読点を直す（英語、一部機種） | 「Change tea to T-E-E」「select」「delete」「undo」 | 自動句読点のオン・オフ |
| Windows の音声入力 | 入力欄に入れる（推測）。「Listening...」が出てから話す | 記述なし | Fluid dictation が話しながら文法・句読点・言いよどみを直す。「Revert」「Undo that」か Ctrl+Z で元に戻す | 「delete that」「select that」 | 起動ボタン、自動句読点、Fluid dictation（既定オン） |
| Gboard の音声入力 | 入力欄（推測）。「Speak now」が出てから話す | 記述なし | Fix it（Pixel 8 以降、英語・米国のみ） | 語を選んで、話す・打つ・候補から選ぶ | Advanced voice typing のオン・オフ |
| （比較軸）macOS のライブキャプション | 専用のウィンドウ。動かせて大きさも変えられる。音がないと隠れる | 記述なし | 該当なし | 該当なし | Keep Onscreen、文字の書体・大きさ・色、背景色 |
| （比較軸）Windows のライブキャプション | 画面の上、画面の下、画面に重ねる（動かせる窓） | 記述なし | 該当なし | 該当なし | 位置、字幕のスタイル、不適切な語の伏せ字 |
| （補足）Google ドキュメントの音声入力 | 文書のカーソル位置 | 灰色の下線の語に、右クリックで候補 | 該当なし | マイクを止めずにカーソルで直せる | 該当なし |

## 3. アプリごとの詳細

### 3.1 VoiceInk（ソース）

#### (1) 途中の文字を出すか、どこに出すか
- ストリーミング対応のモデル（Real-time）を使うときだけ、録音中に途中の文字を出す。設定の説明は「Shows live text while recording with realtime models.」（確認）。`VoiceInk/Features/Settings/Views/SettingsView.swift` L232-L236
- ミニレコーダー（画面下の黒いカプセル）は、文字が来ると幅を 184 から 300 に広げ、角の丸みを 20 から 14 に変え、操作の列の上に文字の欄を足す（確認）。`VoiceInk/Features/Recording/Views/MiniRecorderView.swift` L14-L19、L73-L80、L96-L100
- 文字の欄は高さ 56 の縦スクロールで、12pt、白の 80%、上端を 18% ぼかし、新しい文字が来るたびに一番下までスクロールする。アニメーションは切っている（確認）。`VoiceInk/Features/Recording/Components/RecorderComponents.swift` L305-L337
- ノッチ型のレコーダーでは、ノッチの下に同じ欄を開く（確認）。`VoiceInk/Features/Recording/Views/NotchRecorderView.swift` L25-L39、L214-L225
- 出すのは録音中（`.recording`）だけ。書き起こし中・整形中（`.transcribing`、`.enhancing`）は欄を閉じる（確認）。`MiniRecorderView.swift` L21-L26、`NotchRecorderView.swift` L31-L36
- 入力欄に途中で文字を入れる処理はない。途中の文字は `partialTranscript` に入るだけで、使うのは上の 2 つのビューだけ（確認: `partialTranscript` の参照を検索した）。

#### (2) 未確定の文字の見せ方
- 確定した区間（`committed`）と途中の文（`partial`）を空白でつなぎ、1 つの文字列にして渡す。見た目は区別しない（確認）。`VoiceInk/Features/Recording/Streaming/StreamingTranscriptionService.swift` L378-L417
- 確定のたびに確定済みの全文で更新し、表示が空にならないようにしている。コメントは「Refresh the live preview so it keeps showing the full running transcript after a commit」（確認）。同 L391-L395

#### (3) 整形の前後
- 録音中の欄には整形後の文を出さない（確認、上の表示条件による）。整形の差分を見せる画面、入力前の確認は見つからなかった（検索語: diff、enhancedText、originalText。`Features` の下）。

#### (5) オン・オフ
- 設定「Live Text Display」。既定はオン（確認）。`VoiceInk/App/Configuration/AppDefaults.swift` L12、L60
- モードごとに Real-time を切り替えられる。Real-time 専用のモデルでは切れない（確認）。`VoiceInk/Features/ModelLibrary/Models/TranscriptionRealtimeSupport.swift` L4-L25、`Features/Modes/Views/ModeConfigFormView.swift` L265-L276

### 3.2 OpenWhispr（ソース）

#### (1) 途中の文字を出すか、どこに出すか
- 設定「Live Transcription Preview」。説明は「Show transcription in a floating window before cleanup」。日本語訳は「クリーンアップ前にフローティングウィンドウで文字起こしを表示」。既定はオフ（確認）。`src/locales/en/translation.json` L2631-L2632、`src/locales/ja/translation.json` L2338、`src/stores/settingsStore.ts` L1731
- 出すのは、この Mac で動くモデルを使うとき（`useLocalWhisper`）と、自分の API キーでクラウドのストリーミングを使うとき（`byok`）だけ（確認）。`src/helpers/audioManager.js` L1653-L1657、`src/utils/transcriptionPreview.ts` L27-L35
- パネルは全文を出し、下に吸い付くようにスクロールする。手でスクロールして過去の部分も読める（確認）。`src/components/dictation/LiveTranscriptPanel.tsx` L34-L41、L72-L81
- 新しい行でパネルが押し上げられないよう、見えない場所で先に文字を組んで高さを測り、ウィンドウの大きさが追いついてから見える文字を更新する。コメントは「This prevents a new line from pushing the panel upward before its BrowserWindow catches up.」（確認）。`src/hooks/useLiveTranscriptPanel.js` L117-L120
- 描き直しは 50 ms ごとにまとめる（確認）。同 L10

#### (2) 未確定の文字の見せ方
- 状態は listening、live、cleanup、final の 4 つ（確認）。`LiveTranscriptPanel.tsx` L8
- live と cleanup の間は、末尾の文だけを光らせる（シマー）。前の部分はそのまま（確認）。`LiveTranscriptPanel.tsx` L43-L47、L77-L80
- 光らせる範囲は、末尾から空白で区切って 6 語。コメントは「Keep the newest phrase visually active without making the completed body flicker.」（確認）。`src/utils/liveTranscriptPresentation.ts` L6-L39
- 日本語はスペースで区切られないので、全文が 1 語と数えられ、全体が光る（推測: コードの区切り方からの推論。画面では確かめていない）。
- シマーは、文字色を透明にして、背景のグラデーションを文字の形に切り抜き、2.2 秒で流す（確認）。`src/styles/dictation-panel.css` L517-L541

#### (3) 整形の前後
- 話し終えると、整形があるとき（`useCleanupModel` など）は cleanup の状態にして、ライブの文を光らせたまま残す（確認）。`audioManager.js` L6408-L6415、`useLiveTranscriptPanel.js` L377-L381
- 結果が出ると、パネルの文を最終の文に一度で置き換え、4 秒後に閉じる。マウスを載せている間は閉じない（確認）。`useLiveTranscriptPanel.js` L13、L299-L320、L382-L391、`src/hooks/useAudioRecording.js` L708
- 置き換える文は、入力欄に入れる文と同じ `result.text`（確認）。整形済みの文と思われる（推測）。
- 差分は出さない。コピーとパネルを閉じるボタンがある（確認）。`LiveTranscriptPanel.tsx` L103-L122
- 入力前の確認はない。パネルの表示と入力は並行する（推測: `completeDictationPreview` の後に自動貼り付けの処理が続く。`useAudioRecording.js` L708-L720）。

#### (5) オン・オフ
- 上の Live Transcription Preview（確認）。

### 3.3 Handy（ソース）

#### (1) 途中の文字を出すか、どこに出すか
- 設定「Overlay」で None、Minimal、Live を選ぶ。説明は「Live shows transcription in real time as you speak (streaming-capable models only — look for the Streaming badge in the model picker).」（確認）。`src/i18n/locales/en/translation.json` L494-L503
- 既定は Linux で None、それ以外で Live（確認）。`src-tauri/src/settings.rs` L600-L607
- Live は、小さなピル（波形と経過時間）が上に開いてパネルになる形。コメントは「a pill that sculpts open into a panel」（確認）。`src/overlay/RecordingOverlay.tsx` L288-L346
- 位置は画面の上か下を選べる（確認）。`src-tauri/src/settings.rs` L126 付近、`RecordingOverlay.tsx` L60

#### (2) 未確定の文字の見せ方
- バックエンドは、確定部分と未確定部分を分けて送る。型の説明は「`committed` is the append-only, flicker-free prefix; `tentative` is the volatile suffix the model may still rewrite.」（確認）。`src-tauri/src/managers/transcription.rs` L59-L66
- 画面では 2 つを別の `span` に入れるが、未確定部分の CSS は `color: inherit` で、見た目は同じ（確認）。`RecordingOverlay.tsx` L324-L327、`src/overlay/RecordingOverlay.css` L209-L211
- 全体を 15px の斜体で出し、上端をぼかし、末尾に点滅するカーソルを出す（確認）。`RecordingOverlay.css` L178-L199、L215 付近、`RecordingOverlay.tsx` L330
- 手でスクロールして戻れる。一番下の近くにいるときだけ、新しい文に吸い付く（確認）。`RecordingOverlay.tsx` L216-L221

#### (3) 整形の前後
- 話し終えて書き起こし・整形をしている間も、文があればパネルを閉じず、文を残したまま下の列をスピナーと「処理中」に替える。コメントは「so the transcript stays put under a working spinner instead of collapsing and squishing the text mid-stream」（確認）。`RecordingOverlay.tsx` L296-L301、L335-L342
- 整形後の文をパネルに出す処理は見つからなかった（推測: 途中の文を送る `emit_stream_text` の呼び出しは `live.rs` L165 の 1 か所だけ）。

### 3.4 Amical（ソース）

#### (1) 途中の文字
- 録音中の途中の文字は出さない（確認: `apps/desktop/src` と `packages` で partialText、interim、onPartial を検索し、該当なし）。ウィジェットの停止ボタンのコメントは「Stop = commit: finish + transcribe + paste」（確認）。`apps/desktop/src/renderer/widget/pages/widget/components/FloatingButton.tsx` L13

#### (3) 入力前の確認（Draft）
- Draft は、通常のディクテーションと別のショートカット。説明は「Hold to speak an instruction; review the generated text, then insert it」（確認）。`apps/desktop/src/i18n/locales/en.json` L851-L854
- 紹介文は「Dictation types what you say. Draft writes what you mean.」（確認）。同 L238-L251
- 生成した文を幅 560 のパネルに出し、Insert（Enter）、Copy、閉じる（esc）を選ぶ（確認）。`DraftReview.tsx` L45-L47、L90-L120
- パネルを開いたまま話し直すと、その間は操作の列が「Listening…」「Drafting…」の状態表示になり、Enter は効かない（確認）。同 L61-L68、L124-L135
- 差分は出さない（確認: 本文は生成した文だけ。同 L118-L120）。

### 3.5 Whispering（epicenter、ソース）

- 現在の Whispering は、録音を保存して書き起こすメモのアプリで、他のアプリへのディクテーションはない。README は「Dictating into other apps is not part of it.」、未対応の一覧に「System-wide dictation: global shortcuts, push-to-talk, voice-activated recording, and delivering text to the cursor or clipboard automatically.」とある（確認）。`apps/whispering/README.md` L15-L16、L635-L638
- 途中の文字を出す処理も見つからなかった（検索語: partial、interim、realtime、streaming。`apps/whispering`）。

### 3.6 Superwhisper

#### (1)(2) 途中の文字
- 録音ウィンドウは、Realtime 対応のモデルのとき「the window shows your words as you speak」（確認）。https://superwhisper.com/docs/get-started/interface-rec-window.md
- Realtime に対応するのは Nova（クラウド）、Scribe（クラウド、ElevenLabs）、Parakeet（ローカル）。Whisper、S1-Voice、Cohere Transcribe は対応しない。「Realtime needs a Pro license.」（確認）。https://superwhisper.com/docs/common-issues/realtime.md
- 未確定の文字の見せ方は書かれていない（確認、同上の 2 ページ）。
- ミニウィンドウは、録音中は波形だけを出す（確認）。interface-rec-window.md

#### (3) 整形の前後
- 履歴は「the audio, the transcription, and the AI result」を保存し、別のモードで再処理できる。差分や元に戻す操作の記述はない（確認）。https://superwhisper.com/docs/get-started/history.md
- 「Paste result text」をオフにすると、クリップボードに入れるだけになる。「Close after transcription」をオフにすると、貼り付けを検出できなかったときだけウィンドウが残る（確認）。https://superwhisper.com/docs/get-started/settings-advanced.md
- 入力前に整形の前後を比べる画面は見つからなかった。

#### (5) オン・オフ
- Realtime はモードごとのトグル。録音ウィンドウ自体を None にもできる（確認）。realtime.md、settings-advanced.md

### 3.7 Aqua Voice

#### (1)(2) 途中の文字
- 「Realtime Mode: words appear in real time as you talk」。手を使わない入力（Aqua キーの 2 回押し）では既定で「see words live in the Aqua toolbar」（確認）。https://aquavoice.com/llms.txt
- 「Words appear in the Aqua toolbar as you speak and land in the app when you finish.」（確認、同上の Send It の説明）。
- Realtime のページは「Your words appear in the toolbar as you speak」「Your text lands in the app when you finish.」、文は「resolve into clean, punctuated text a beat behind you」（確認）。https://aquavoice.com/realtime
- 未確定の文字の色や下線は書かれていない（確認、同上）。
- Realtime は macOS と Windows のデスクトップ版だけ。iPhone と Android は話し終えてから入力する（確認、同上）。
- Aqua Pet（2026-10-15、v0.21.0）は、Realtime（Max）では「the pet holds up your words as they come in」（確認）。https://aquavoice.com/llms.txt 、https://aquavoice.com/changelog

#### (3) 整形の前後
- 履歴の「Undo」で元の書き起こしに戻る（2025-04-23、v0.3.0）（確認）。https://aquavoice.com/changelog
- 「Paste Only」で、入力するが送信はしない（2026-07-29、v0.18.5）。入力前の確認ではない（確認、同上）。

#### (4) 言い直し
- Realtime で話しながら「change Thursday to Friday」と言うと「the live text updates before anything is sent」（確認）。https://aquavoice.com/realtime

#### (5) オン・オフ
- Settings > Activation の「Realtime always」と「Instant always」。Realtime は Max と Business（無料は最初の 1,000 語まで試せる）。Edit Mode は常に Instant（確認）。https://aquavoice.com/realtime

### 3.8 Wispr Flow

#### (1) 途中の文字
- 最初のディクテーションの記事は、ショートカットを離した後「wait for your formatted text to appear in the field that is focused at that moment」と説明する。録音中に文字を出す記述はない（確認）。https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation
- Flow Bar は「a small floating bubble showing your dictation status: resting, recording, or processing」（確認）。https://docs.wisprflow.ai/articles/1790396454-move-and-dock-the-flow-bar-on-desktop
- 変更履歴にライブの書き起こしがあるのは Notetaker（会議、2026-08-05）だけ（確認）。https://wisprflow.ai/whats-new
- 二次: Android 版の第三者レビュー（Beebom）は「リアルタイムの書き起こしは見えない」と書いていた。根拠にはしていない。

#### (3) 整形の前後
- Undo AI edit: Home タブの最近の履歴の「…」メニューから。元の書き起こしに戻し、Redo AI edit で整形後に戻す。元と整形後が違うときだけ使える（確認）。https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack
- 入力した直後は、アプリの通常の取り消しで貼り付けを戻せる（確認）。https://docs.wisprflow.ai/articles/4283510616-auto-cleanup-control-how-much-flow-edits-your-dictation-beta
- Transforms（選んだ文の書き換え）は、書き換えた後に Flow Bar に「Done. See changes」を出し、差分を開ける（Mac は Opt+O）。差分の画面に Undo がある。取り消し線や色の記述はない（確認）。https://docs.wisprflow.ai/articles/8068950331-how-to-use-transforms-beta

#### (4) 言い直し
- Backtrack: 「Let's do coffee at 2 actually 3.」が「Let's do coffee at 3.」になる。録音中に画面で直る様子の記述はない（確認）。Smart Formatting の記事。

### 3.9 Typeless

- 話し終えると「Your polished writing appears where you began dictating.」。開始の合図として「Voice bar」が出るが、何を表示するかは書かれていない（確認）。https://www.typeless.com/help/quickstart/dictate
- ホームページは「Auto-edits when you change your mind」で、言い直しは「keeps only your final intended message」（確認）。https://www.typeless.com
- 録音中の途中の文字、整形の前後、元に戻す操作の記述は見つからなかった（探した場所: /help/quickstart/dictate、/help/faqs、/help/release-notes、ホームページ）。

### 3.10 Willow Voice

- キーを押すと「a small floating bar appear」、離すと「right where your cursor was」に入る（確認）。https://help.willowvoice.com/en/articles/10876920-dictating-with-willow-voice
- 言い直しの例は「No wait, actually, 5 p.m.」で、前の言い方を直したと判断して文を更新する。録音中に画面で直るかは書かれていない（確認）。https://help.willowvoice.com/en/articles/13183983-voice-commands-and-automatic-formatting-guide
- バーを消すには、設定の General で「Enable Notch View」をオンにする（確認）。https://help.willowvoice.com/en/articles/13706888-how-do-i-get-rid-of-the-floating-app-icon-or-the-bar
- 録音中の途中の文字は、公式ページに記述がない（探した場所: 上の 3 記事、/features/dictation、ヘルプの 2 つのコレクション）。

### 3.11 Spokenly

- ドキュメントの入門は「Let go and your words appear in the active app automatically.」（確認）。https://spokenly.app/llms-full.txt L184
- 公式ブログは、OpenAI のストリーミングを有効にすると「words appear on screen while you are mid-sentence rather than after you stop」と書く。出る場所（録音のオーバーレイか、入力欄か）は書かれていない（確認）。https://spokenly.app/blog/gpt-transcribe
- 辞書の説明に「In live transcription, only the first 50 terms apply.」とあり、対応モデルに Soniox Realtime がある（確認）。llms-full.txt L112、L127
- 未確定の文字の見せ方、整形の前後の記述は見つからなかった（探した場所: llms-full.txt 全体。検索語: stream、real-time、live、partial、interim、overlay）。

### 3.12 Monologue

- iOS v1.1.2（2026-08-15）「Real-time dictation is now the default for a faster writing experience.」（確認）。https://www.monologue.to/changelog
- macOS v1.5.0（2026-08-24）の Dot は、入力欄の横で「shows when Monologue is listening and turning your speech into text」、終わると「inserts the finished text there」（確認、同上）。文字そのものを出すかは書かれていない。
- Mac の Indicator は Classic（画面の端）、Mini（入力中の文の近く）、None（確認）。https://www.monologue.to/docs/dictation/mac-preferences

### 3.13 MacWhisper

- ディクテーションの記事は、ショートカットで「transcribe audio into any text field directly」と説明するだけ。録音中の表示は書かれていない（確認）。https://docs.macwhisper.com/article/14-how-to-use-the-dictation-feature 。この記事は古い可能性がある（前回のメモで、検索結果の更新日が約 600 日前だった）。
- ホームページに「Real-time dictation for messages, notes, and documents」とあるが、画面の説明はない（確認）。https://www.macwhisper.com

### 3.14 macOS のディクテーション（Apple）

- 挿入位置にカーソルを置いて始める。「When the cursor is highlighted and pulsing, or you hear the tone that signals your Mac is ready for dictation, dictate your text.」（確認）。https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac
- 「The new line or new paragraph appear when you’re done dictating.」（確認、同上）。改行以外は話しながら入力欄に入ると読める（推測）。
- 「Ambiguous text is underlined in blue.」別の候補をクリックで選ぶ（確認、同上）。
- Apple シリコンの Mac では「you can still use the keyboard while you speak」。打っている間はカーソルの点滅が止まり、やめると再開する（確認、同上）。
- 複数の言語では、カーソルの横の言語の表示をクリックして切り替える（確認、同上）。
- 開発者向け: macOS の `NSTextAlternatives` は「To support dictation, for example, you might use NSTextAlternatives to present a list of alternative interpretations for a word or phrase the user speaks.」（確認）。https://developer.apple.com/documentation/appkit/nstextalternatives
- 開発者向け: `NSTextInputClient` の `setMarkedText` は、変換中の文字（marked text）を「the receiver is expected to render the marked text with distinguishing appearance」と定める（確認）。https://developer.apple.com/documentation/appkit/nstextinputclient/setmarkedtext(_:selectedrange:replacementrange:)
- ディクテーションの途中の文字が marked text として入るのか、確定した文字として入って後から置き換わるのかは、公式資料に書かれていない。

### 3.15 iOS のディクテーション

- 「the keyboard stays open during Dictation so you can easily switch between touch and voice to enter text」（確認）。https://support.apple.com/guide/iphone/dictate-text-iph2c0651d2/ios
- iOS 27 では「dictation uses an on-device model to improve spelling, punctuation, and capitalization」（英語、iPhone 17 Pro などの一部機種）（確認、同上）。直した前後を見せるかは書かれていない。
- 声で直す: 「Change tea to T-E-E」、「select」「delete」の後に語句、「undo」「redo」（確認、同上）。
- 開発者向け: `UITextInput` の `insertDictationResultPlaceholder` は「provide a specific rectangle for the placeholder animation while the dictation results are being processed」（確認）。https://developer.apple.com/documentation/uikit/uitextinput/insertdictationresultplaceholder 。あいまいな結果は `UIDictationPhrase` が別の候補を持つ（確認）。https://developer.apple.com/documentation/uikit/uidictationphrase

### 3.16 Windows の音声入力（Win+H）

- 「Wait for the "Listening..." alert before you start speaking.」（確認）。https://support.microsoft.com/en-us/windows/use-voice-typing-to-talk-instead-of-type-on-your-pc-fec94565-c4bd-329d-e59a-af033fa5689f
- 設定は、音声入力の起動ボタン（launcher）と自動句読点（確認、同上）。
- Fluid dictation（Copilot+ PC、英語）は「It automatically corrects grammar, punctuation, and filler words as you speak」。既定でオン（確認、同上）。
- 戻す操作は「simply say “Revert” or “Undo that” or Ctrl+Z on your keyboard and Voice typing will restore the original version.」（確認、同上）。
- 「delete that」「select that」で直す（確認、同上）。
- 途中の文字の見せ方（下線、薄い色）は書かれていない。

### 3.17 Gboard の音声入力

- 「When you see "Speak now," say what you want written.」。直すときは、語を長押しして、マイクを押して言い直す（確認）。https://support.google.com/gboard/answer/2781851?hl=en
- Advanced voice typing（Pixel 6 以降、日本語を含む 6 言語）は、マイクを入れたまま打てる（「Type even if the mic is still on」）。聞き間違いは語を選んで、話す・打つ・綴る・候補から選ぶ。「Fix it」は Pixel 8 以降、英語・米国だけ（確認）。https://support.google.com/gboard/answer/11197787?hl=en
- Google の公式ブログ（2019-03-12）は、端末上の認識器が「as you speak, it outputs words character-by-character」と説明する（確認）。https://research.google/blog/an-all-neural-on-device-speech-recognizer/
- 開発者向け: Android の入力方式は、変換中の文字（composing text）を `setComposingText` で置き換える。「Replace the currently composing text with the given text」「If no style object attached to the text, the default style for composing text is used.」（確認）。https://developer.android.com/reference/android/view/inputmethod/InputConnection
- Gboard の音声入力が途中の文字を composing text として入れるかは、公式資料に書かれていない。

### 3.18 比較軸: macOS と Windows のライブキャプション

- macOS: 「audio is transcribed in real time in the Live Captions window」。音がないと自動で隠れ、「Keep Onscreen」で出したままにできる。書体、大きさ、文字色、背景色を変えられ、窓の大きさと位置も変えられる。パソコンの音とマイクの音を切り替えられる（確認）。https://support.apple.com/guide/mac-help/use-live-captions-mchldd11f4fd/mac
- Windows: 位置は「Above screen」「Below screen」「Overlaid on screen」。重ねる場合は「an overlay window which you can reposition as needed to avoid obscuring other apps in use」。字幕のスタイルを選べる。「Filter profanity」がある。マイクの音は設定でオンにする（確認）。https://support.microsoft.com/en-us/windows/use-live-captions-to-better-understand-audio-b52da59c-14b8-4031-aeeb-f6a47e6055df
- どちらも、一度出した字幕を後から直すかどうか、未確定の語をどう見せるかは書かれていない（確認、同上の 2 ページ）。

### 3.19 開発者向けの指針（Apple、Microsoft）

途中の文字の見せ方を、OS の作り手が開発者に勧めている箇所。

- Apple の `SpeechTranscriber` の volatileResults は「Provides tentative results for an audio range in addition to the finalized result.」（確認）。https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption/volatileresults 。結果は「each phrase is sent one or more times as the interpretation gets better and better until it is finalized」（確認）。https://developer.apple.com/documentation/speech/speechtranscriber/result
- Apple の公式サンプルは、確定前の文（volatile）を `.purple.opacity(0.4)` にし、確定した文の後ろにつなげて 1 つの `Text` に出す。確定したら確定前の文を空にする（確認）。`SwiftTranscriptionSampleApp/Recording and Transcription/Transcription.swift` L64-L73、`SwiftTranscriptionSampleApp/Views/TranscriptView.swift` L98（https://developer.apple.com/documentation/speech/bringing-advanced-speech-to-text-capabilities-to-your-app の配布物）
- Microsoft の連続ディクテーションのガイドは、HypothesisGenerated の途中の結果を「Show these to the user as they continue speaking and reassure them that processing is still active. Once confidence is high and a recognition result has been determined, replace the interim Hypothesis results with the final Result」と書く。例では、確定した文の後ろに仮説と「...」を付けて入力欄に出す（確認）。https://learn.microsoft.com/en-us/windows/apps/design/input/enable-continuous-dictation
- Microsoft の音声のガイドは「Provide ongoing recognition feedback to minimize any apparent lack of response while recognition is being performed.」「Stop recognition if input is detected from a device other than speech recognition, such as touch or keyboard.」と書く（確認）。https://learn.microsoft.com/en-us/windows/apps/design/input/speech-interactions

### 3.20 そのほか

- Google ドキュメント: 文字はカーソル位置に入る。「right-click on words underlined in gray」で候補を見る。「move your cursor to the mistake and fix it without turning off the microphone」（確認）。https://support.google.com/docs/answer/4492226?hl=en
- Microsoft Word: 「Start speaking to see text appear on the screen.」。「Markings may appear under words with alternates we may have misheard.」（確認）。https://support.microsoft.com/en-us/office/dictate-your-documents-in-word-3876e05f-3fcc-418f-b8ab-db7ce0d11d3c

## 4. Koebumi への示唆

Koebumi の現状（コードで確認した範囲）。録音中と処理中に、バーの上の札に最後の 2 行まで出す（全角 2・半角 1 と数えて 100 まで、先頭を「…」で省く）（`Sources/Koebumi/UI/VoiceBar.swift` L146-L190）。札は Qwen3-ASR の書き起こしを 0.7 秒ごとに書き直した結果で、30 秒を超えた区間だけを確定する（`Sources/Koebumi/Speech/LocalSpeechRuntime.swift` L336-L344、L403-L421）。札の表示をオン・オフする設定はない（`Core/Settings.swift` を検索した）。入力欄のカーソルの矩形を取る処理はまだない（`Sources` で `kAXBoundsForRangeParameterizedAttribute` を検索し、該当なし）。履歴には AI の変更の表示がある（`UI/HistoryView.swift` L250、L277）。

### 4.1 見つかったことを A〜E の案で整理する

| 案 | 当てはまる例 | 違い・補足 |
|---|---|---|
| A: バーの上の札 | Superwhisper の録音ウィンドウ、Aqua Voice のツールバー（推測: 場所の言葉からの推論）、OpenWhispr のフローティングパネル | OpenWhispr は全文を出し、スクロールできる。札の大きさが文に合わせて変わる |
| A と B の中間: バー自体が上に広がる | VoiceInk（184 から 300 に広がり、上に 56 の欄）、Handy（ピルが上に開いてパネルになる） | 札を別に出さず、バーと 1 つの面にしている。どちらも高さを決めて、上端をぼかしてスクロールする |
| B: バーの中に 1 行 | 見つからなかった | Aqua Voice のツールバーの行数が不明で、B の可能性もある |
| C: カーソル位置に薄い文字を重ねる | 見つからなかった | OS 標準のディクテーション（Apple、Windows、Google）は、薄い文字を重ねるのではなく、入力欄に本物の文字を入れる。Monologue の Dot と Mini は入力欄の近くに出るが、文字を出す記述はない |
| D: 字幕 | macOS と Windows のライブキャプションだけ | ディクテーションのアプリには見つからなかった。未確定の部分を薄くする手本は、Apple のサンプル（薄い紫）と Microsoft のガイド（「...」を付ける） |
| E: 大きめのパネル、整形の差分 | 録音中に差分を見せるものは見つからなかった | 近いのは OpenWhispr（全文のパネル、整形中は光らせ、最終の文に置き換えて 4 秒残す）と Amical の Draft（入力前に確認、差分なし）。差分は事後の画面にある（Wispr Flow の View Diff、Undo AI edit） |

### 4.2 どの案が多く使われているか

- 他社のアプリで途中の文字を出すものは、すべて自分の録音バーやパネルに出す（A 系）。入力欄に文字を入れるものはなかった（確認、3.1〜3.13 の範囲）。
- OS 標準のディクテーションは、入力欄に直接入れる（確認: Apple、Google ドキュメント、Word の記述）。他社のアプリがこの形を取らないのは、どのアプリにも同じように文字を入れて後から書き直す手段がないからだと思われる（推測）。Koebumi も他社と同じく、途中の書き起こしは札にだけ渡している（確認: `Core/DictationController.swift` L288-L293）。
- AI 整形を売りにするアプリ（Wispr Flow、Typeless、Willow Voice）は、公式資料の範囲で途中の文字を出さない。整えた文だけを見せる方針と思われる（推測）。Aqua Voice は Realtime を上位のプランの機能にして、既定（Instant）では出さない（確認）。
- 途中の文字を出すアプリは、どれもオン・オフの設定を持つ（確認: VoiceInk、OpenWhispr、Handy、Superwhisper、Aqua Voice）。Koebumi も設定を用意する方が、他社に合う（推測）。

### 4.3 日本語入力（IME の変換中の文字）とぶつからないか

- A、B、D、E は入力欄に触れないので、IME の変換中の文字とは競合しない（推測）。他社のアプリが A 系を選ぶ理由の 1 つでもあると思われる（推測）。
- OS は、変換中の文字を入力欄の中で区別して描くよう求めている（確認: Apple の `setMarkedText` の「distinguishing appearance」、Android の composing text の既定の書式）。日本語の IME では、変換中の文字は下線付きで出る（推測: 一般的な振る舞い。今回は公式資料で確かめていない）。
- C 案の心配は 3 つある（いずれも推測）。
  1. 薄い文字が IME の変換中の文字に似て見える。利用者が Enter で確定しようとすると、Enter は入力欄のアプリに届く。チャットでは送信になってしまう。
  2. 録音を始めたときに変換中の文字が残っていると、カーソルの位置が変換中の文字の後ろになり、薄い文字がそれに重なる。
  3. 録音中にキーボードで打つと、重ねた文字と打った文字がずれる。Microsoft のガイドは、キーボードの入力があったら認識を止めるよう勧めている（確認）。macOS のディクテーションは、打っている間は聞き取りを止める（確認）。
- 日本語の IME と OS 標準のディクテーションを同時に使うときの振る舞いは、公式資料に見つからなかった（5 を参照）。

### 4.4 整形で文が変わったときに文字が跳ねる問題

各アプリの扱いは 4 通りに分かれる。

- 整形後の文は録音中の表示に出さない。VoiceInk は録音が終わると欄を閉じる（確認）。Handy は処理中も文を残し、パネルを閉じない（「collapsing and squishing the text mid-stream」を避ける、確認）。整形後の文は入力欄にだけ入る（推測）。
- 一度で置き換えて、少しだけ残す。OpenWhispr は整形中はライブの文を光らせたまま残し、結果が出たら最終の文に置き換えて 4 秒残す（確認）。行が増えてパネルが押し上がらないよう、先に高さを測ってから表示を更新する（確認）。
- 話している間に少し遅れて整える。Aqua Voice は文が「a beat behind you」整った文になる（確認）。Windows の Fluid dictation は話しながら直して入力欄に入れ、「Revert」で元に戻す（確認）。
- そもそも途中の文字を出さない。Wispr Flow、Typeless、Willow Voice（確認: 記述の範囲）。跳ねる問題を避ける方法でもある（推測）。

Koebumi に当てはめると、次のようになる（推測を含む提案）。

- 札は A のまま保ち、録音中は Qwen3-ASR の書き起こしだけを出す。整形後の文は札に出さず、入力欄にだけ入れる。こうすれば札の文字は跳ねない。VoiceInk と Handy と同じ考え方。
- 「大主 → 大衆 → 来週」のように書き直しで変わる部分は、前の書き起こしと同じ先頭を濃く、変わった後ろを薄くする（プロトタイプの D 案の `stability()` と同じ考え方）。手本は Apple のサンプル（確定前を不透明度 0.4）と Handy の committed と tentative の分け方。Koebumi の `LocalModelSession` には、30 秒で確定した区間（`committed`）がすでにある。
- 整形の差分（E）は、録音中の札ではなく、入力の後に見せる方が他社の例に合う。Wispr Flow は Flow Bar の「See changes」から差分を開き、Undo できる。Koebumi には履歴の差分の表示があるので、使い回せる。
- 札の表示をオン・オフする設定を足す。他社は既定オン（VoiceInk、Handy）と既定オフ（OpenWhispr、Aqua Voice の Instant）に分かれる。

## 5. わからなかったこと

- Wispr Flow のデスクトップ版が、録音中に文字を出すかどうか。公式の記事は「離した後に入力欄に出る」とだけ書き、出さないとも明記していない。二次の情報（Android 版のレビュー）は出ないと書いていたが、根拠にしていない。
- Aqua Voice の Realtime の見た目。ツールバーに何行出るか、未確定の語を区別するか。公式ページに図の説明がなく、紹介動画は見ていない。
- Superwhisper の Realtime の見た目（未確定の語の区別、整形後に録音ウィンドウの文を置き換えるか）。
- Typeless と Willow Voice が録音中に文字を出すかどうか。出すとも出さないとも書いていない。Typeless のリリースノートは個別のページを読めなかった。
- Spokenly の途中の文字の場所（オーバーレイか、入力欄か）。Monologue の Dot と Mini、iOS の「Real-time dictation」が文字を出すかどうか。
- MacWhisper のディクテーション中の表示。検索結果の要約にはリアルタイムの字幕の機能（Pro）があったが、ホームページを取得した本文では確かめられなかった。
- macOS のディクテーションの途中の文字が、marked text として入るのか、確定した文字として入って後から置き換わるのか。日本語の IME の変換中に始めたときの振る舞い。
- Gboard と Windows の音声入力の途中の文字の見せ方（下線つきの変換中の文字として入るか）。ライブキャプションが一度出した字幕を直すか。
- OpenWhispr の日本語のシマーが本当に全体にかかるか。コードからの推論で、画面では確かめていない。
- 動画でしか説明していない情報は、どの製品も見ていない。
