# Windows 版 フェーズ 0: 実機で確かめたこと

実施日: 2026-10-27。[Windows 版の設計](../windows.md)の「フェーズ 0」の 5 項目と、「気をつけること」に挙げた 2 つ（クリップボードの履歴、変換中の貼り付け）を、Windows の実機で確かめた。試作は [`windows/spikes/Phase0`](../../windows/spikes/Phase0/README.md)（.NET 9・WPF）。

使った PC: Windows 11 Pro 10.0.26200（x64）、Microsoft IME（日本語）。アカウントは管理者だが、アプリは管理者でない権限で動く（UAC は既定）。リモート デスクトップで接続して試した。

各結果に、確かめ方を付けた。

- 自動: 試作が SendInput でキーとマウスを送り、UI Automation で読み直して確かめた
- 本人: 本人がキーボードで Ctrl+Win を押して確かめた。リモート デスクトップ経由で、Ctrl は右 Ctrl として届いた。PC に直接つないだキーボードでは試していない
- 未確認: 試せなかった

## 1. 要約

- 5 項目とも、設計の方針（WPF、低レベルのキーボードフック、クリップボードと Ctrl+V、UI Automation）を変えるような問題はなかった
- 設計に次の 4 つを足す
  1. 音声バーには `WS_EX_NOACTIVATE` が要る。`ShowActivated = false` だけでは、バーのボタンを押したときにフォーカスを奪う
  2. Chromium のアプリ（Chrome・Edge と、Slack・Spark などの Electron）では、最初の読み取りでフォーカスが外側の枠を指す。30 ms 待って取り直すと読める。また、カーソルの前後を文字数で広げると入力欄を越えてページの文字まで入るので、入力欄の範囲で切る
  3. 変換中（未確定の文字がある）に貼り付けると、アプリによって結果が違う。メモ帳は未確定の文字を確定してから貼り付ける。Chrome・Edge は未確定のまま残してその後ろに貼り付け、そのあと Esc で変換を取り消すと未確定の読みに戻る。未確定の文字は UI Automation の `GetActiveComposition` で見分けられる
  4. 管理者として動くアプリが前面のあいだは、ショートカットを押しても検出できない（フックにキーが届かない）。前面の切り替えを受け取って見分け、そのときに知らせる
- 試せなかったもの: Word と Outlook（クラシック）は、この PC の Office（LTSC Professional Plus 2021）がライセンス認証されておらず、編集できなかった。Teams・新しい Outlook・Gmail は試していない

## 2. 結果

### 2.1 キーボードフック（項目 1）

方式: Ctrl を先に押したら、Win の押下と離しを飲み込む。Win を先に押したら、Win は通す（押した時点ではショートカットかどうかわからない）。離すときは、割り当てのない仮想キー 0xE8 を挟んでから Win の離しを送り直す（AutoHotkey の MenuMaskKey と同じ）。

| 押し方（自動） | 開始・終了を取れたか | スタートメニュー | 入力先のアプリに届いたキー |
|---|---|---|---|
| 対照: Win だけ | （ショートカットではない） | 開いた | Win |
| Ctrl↓ Win↓ Win↑ Ctrl↑ | 取れた | 開かない | Ctrl だけ |
| Ctrl↓ Win↓ Ctrl↑ Win↑ | 取れた | 開かない | Ctrl だけ |
| Win↓ Ctrl↓ Ctrl↑ Win↑ | 取れた | 開かない | Win・Ctrl・0xE8 |
| Win↓ Ctrl↓ Win↑ Ctrl↑ | 取れた | 開かない | Win・Ctrl・0xE8 |
| Ctrl と右 Win | 取れた | 開かない | Ctrl だけ |
| Ctrl+Win を 1.5 秒押し続ける | 取れた | 開かない | Ctrl だけ |
| 比べるため: 何も飲み込まない（Ctrl が先・Win が先） | 取れた | 開かない | Ctrl と Win |
| 右 Ctrl だけ | 取れた | ー | なし |
| 無変換だけ（日本語入力オン） | 取れた | ー | なし。日本語入力はオンのまま |

- 対照の「Win だけ」でスタートメニューが開いたので、SendInput で送ったキーでもスタートメニューの動きを確かめられている
- 何も飲み込まなくても、スタートメニューは開かなかった。Win の前後に Ctrl を押すと開かないようだ。飲み込むのは、入力先のアプリに Win を見せないため
- フックのコールバックにかかった時間は、最長 1.34 ms。押されたままのキーは残らなかった
- 本人: Ctrl+Win を 15 回押した（メモ帳、Slack、Spark、Windows Terminal、T3 Code、エクスプローラー、Windows の検索）。15 回とも開始と終了を取れて、スタートメニューは開かなかった。押した順は、すべて Ctrl が先だった
- 本人のキーには、フックで injected の印が付かなかった。印が付いたのは、リモート デスクトップが修飾キーの状態を合わせるときに送る Ctrl だけだった

### 2.2 音声バー（項目 2）

メモ帳を前面にして、音声バーを出した。

| 窓の設定（自動） | 出したとき | 音量の表示を動かしたとき | 出している間に打った文字 | バーの「×」を押したとき |
|---|---|---|---|---|
| `ShowActivated = false` と `WS_EX_NOACTIVATE`（案） | メモ帳のまま | メモ帳のまま | メモ帳に入る | メモ帳のまま。クリックはボタンに届く |
| `ShowActivated = false` だけ | メモ帳のまま | メモ帳のまま | メモ帳に入る | 試作の窓が前面になる |
| WPF の既定 | 試作の窓が前面になる | ー | メモ帳に入らない | ー |

- 隠して出し直しても、案の設定ではメモ帳のままだった
- 本人: 15 回とも、音声バーを出しても前面のアプリは変わらなかった

### 2.3 Ctrl+V の貼り付け（項目 3）

クリップボードに文を入れて SendInput で Ctrl+V を送り、600 ms 後に元のクリップボードに戻した。貼り付けた文は「明日の会議は4時にしてください。Claude Code 🙂」（日本語・英語・絵文字）。

| アプリ | 日本語入力オフ | 日本語入力オン | 変換中（kaigi と打って未確定） | 確かめ方 |
|---|---|---|---|---|
| メモ帳 | 入る | 入る | 未確定の「かいぎ」を確定し、その後ろに入る | 自動 |
| Chrome（textarea・contenteditable） | 入る | 入る | 未確定のまま残り、その後ろに入る | 自動 |
| Edge（textarea・contenteditable） | 入る | 入る | Chrome と同じ | 自動 |
| Slack・Spark・Windows Terminal・T3 Code・エクスプローラー | 入る | 未確認 | 未確認 | 本人 |
| Word・Outlook（クラシック） | 未確認（Office がライセンス認証されておらず、編集できない） | | | |
| Teams・新しい Outlook・Gmail | 未確認 | | | |

- Ctrl+V を送ってから、UI Automation で文が読めるまで 40〜80 ms
- Slack・Spark（Electron）でも、600 ms 後に元のクリップボードを戻す前に貼り付けが終わった
- 元のクリップボード（本人の環境では 7 形式）は、毎回戻せた

変換中の動きを、印の文字（A〜D。日本語入力を通さずに打つ）を挟んで詳しく見た（自動）。

| 操作 | メモ帳 | Chrome・Edge |
|---|---|---|
| A、貼り付け、B（日本語入力オフ） | A[P1]B | A[P1]B |
| asita と打つ（未確定） | A[P1]Bあした | A[P1]Bあした |
| 貼り付け | A[P1]Bあした[P2] | A[P1]Bあした[P2] |
| C を打つ | A[P1]Bあした[P2]C | A[P1]Bあした[P2]C |
| kyou と打ってスペースで変換 | A[P1]Bあした[P2]C今日 | A[P1]B明日協[P2]C |
| 貼り付け | …C今日[P3] | A[P1]B明日協[P3][P2]C |
| D を打つ | …C今日[P3]D | A[P1]B明日協[P3]D[P2]C |
| Esc を 2 回 | 変わらない | A[P1]Bあしたきょう[P3]D[P2]C |

- メモ帳は、貼り付けたときに未確定の文字を確定する
- Chrome・Edge は、貼り付けても未確定の「あした」を確定しない。続けて打った「kyou」が同じ未確定の文字に足され、「あしたきょう」がまとめて「明日協」に変換された。Esc で変換を取り消すと、未確定の文字に戻る
- 未確定の文字は、UI Automation の `TextEditPattern.GetActiveComposition` で、メモ帳でも Chrome でも「あした」と読めた

### 2.4 クリップボードの履歴（気をつけること）

- `ExcludeClipboardContentFromMonitorProcessing`、`CanIncludeInClipboardHistory`（0）、`CanUploadToCloudClipboard`（0）の 3 つの形式を一緒に入れると、クリップボードの履歴（Win+V）に入らなかった（自動。`Clipboard.GetHistoryItemsAsync` で確かめた）
- 同じ形式を付けずに入れた対照の文は、履歴に入った
- 元のクリップボードを戻すときも同じ形式を付けた。履歴の件数は増えなかった。付けずに戻しても件数は増えなかった（同じ内容は 1 件にまとまる）
- 本人の確認でも、15 回とも貼り付けた文は履歴に残らなかった

### 2.5 UI Automation の読み取り（項目 4）

COM の UI Automation（`IUIAutomation`）で、Mac 版の `SurroundingTextReader` と同じものを読んだ。カーソルの前 300 字と後 1,000 字、ウィンドウの文字（入力欄の前 700 字・後 1,000 字）。時間は、フォーカスのある要素を取ってから全部を読み終えるまで。

| アプリ | 1 回目 | 2 回目から | カーソル位置の取り方 | 確かめ方 |
|---|---|---|---|---|
| メモ帳 | 44 ms | 26 ms | TextPattern2.GetCaretRange | 自動 |
| Word（読み取りだけ） | 88〜126 ms | 77〜106 ms | TextPattern2.GetCaretRange | 自動 |
| Chrome（textarea・contenteditable） | 95 ms（取り直し 1 回） | 25 ms | TextPattern.GetSelection | 自動 |
| Edge（textarea・contenteditable） | 91〜93 ms（取り直し 1 回） | 20 ms | TextPattern.GetSelection | 自動 |
| Slack | 104 ms（取り直し 1 回） | 26 ms | TextPattern.GetSelection | 本人 |
| Spark（メール） | 149 ms（取り直し 2 回） | ー | TextPattern.GetSelection | 本人 |
| T3 Code | 73 ms（取り直し 1 回） | ー | TextPattern.GetSelection | 本人 |
| Windows Terminal | 28 ms | 15 ms | TextPattern.GetSelection | 本人 |
| エクスプローラー（アドレスバー） | 139 ms（要素 318 個） | ー | TextPattern2.GetCaretRange | 本人 |
| Gmail・Teams・Outlook | 未確認 | | | |

- どのアプリも 0.3 秒以内に読めた
- Chromium のアプリは、UI Automation の問い合わせを受けてから、ページのアクセシビリティの木を作り始める。そのため最初の `GetFocusedElement` は、外側の枠（`Pane`、FrameworkId は `Chrome`）を返し、テキストのパターンを持たない。30 ms 待って取り直すと、入力欄（Slack は Quill の `ql-editor`、Spark は CKEditor）が取れた
- Chromium では、カーソルの範囲を `MoveEndpointByUnit` で文字数だけ広げると、入力欄を越えてページのほかの文字まで入った。入力欄の `DocumentRange` の端で切ると、入力欄の中だけになった
- ウィンドウの文字は、窓の木を 1 回の呼び出しでまとめて写し（`BuildUpdatedCache` と `TreeScope_Subtree`）、手元でたどった。13〜132 ms（要素 14〜318 個）。Mac 版と同じく 1 段ずつたどる方法（0.3 秒・2,500 要素の上限つき）でも 25〜54 ms で、大きな差はなかった
- 試験用のページでは、入力欄より前のチャットの発言と、入力欄より後の返信の引用を、Mac 版と同じく分けて読めた
- UI Automation の `TextRange.Select` で、メモ帳のカーソルを置けた（フェーズ 3 の「AI の整形を元に戻す」で使う）

### 2.6 管理者として動くアプリ（項目 5）

タスク マネージャーで試した。管理者のアカウントなら、確認なしで管理者として起動する。

- 見分け方: 前面の窓のプロセスのトークンを `OpenProcess`（`PROCESS_QUERY_LIMITED_INFORMATION`）と `OpenProcessToken`（`TOKEN_QUERY`）で開き、整合性レベルが自分より上（High と Medium）かを見る。管理者として動くプロセスにも使えた（自動）
- 前面の切り替えは、`SetWinEventHook` の `EVENT_SYSTEM_FOREGROUND` で受け取れた。タスク マネージャーに切り替わったことを、自動の試験と本人の確認の両方で見分けられた。本人の確認では、そのとき音声バーに「管理者として動いているアプリには入力できません」を出した
- 前面がタスク マネージャーのとき、SendInput は送った数を返し、エラーも出ないが、キーは捨てられた。フックにも届かなかった（自動）
- 本人がタスク マネージャーを前面にしていた約 25 秒のあいだ、フックには Ctrl・Win が 1 つも届かなかった。そのあいだに Ctrl+Win を押したのは本人の申告による
- UI Automation で読めた要素は 0 個。`WM_CLOSE` も拒否された（`ERROR_ACCESS_DENIED`）

### 2.7 そのほかにわかったこと

- リモート デスクトップを切断したセッションでは、SendInput が `ERROR_ACCESS_DENIED` で失敗し、前面の窓もない。Chrome はページの中身を UI Automation に出さなかった（ブラウザーの枠だけ）。試験はセッションをつないで行う
- メモ帳で、SendInput で文字を打った直後の Ctrl+A が効かないことがあった（自動）。製品では Ctrl+A を使わないので、原因は追っていない

## 3. 設計に足すこと

[docs/windows.md](../windows.md) に反映した。

- ショートカット: Ctrl が先なら Win を飲み込み、Win が先なら離すときに 0xE8 を挟む。貼り付けは、修飾キーをすべて離してから送る（Win を先に押したときは Win を取り消せないので、Win+Ctrl+V になる。Windows 11 では音の出力の切り替えを開くショートカット。これは試していない）
- 音声バー: `ShowActivated = false` と `WS_EX_NOACTIVATE`（と `WS_EX_TOOLWINDOW`）
- 貼り付け: 履歴に残さない 3 つの形式を、貼り付ける文と戻す元の内容の両方に付ける。変換中の扱いを決める（下の「確かめていないこと」）
- 画面の文脈: Chromium は 30 ms ずつ数回取り直す。カーソルの前後を入力欄の範囲で切る。ウィンドウの文字は 1 回でまとめて写す
- 管理者として動くアプリ: 前面の切り替えで整合性レベルを見て、上なら音声バーで知らせる

## 4. 確かめていないこと

- PC に直接つないだキーボードで押した Ctrl+Win（Win を物理的に押したときのスタートメニュー）。本人の確認はリモート デスクトップ経由で、すべて Ctrl が先だった
- Word・Outlook（クラシック）・Teams・新しい Outlook・Gmail での貼り付けと読み取り
- Electron のアプリで、日本語入力がオンのときと変換中の貼り付け
- 変換中に貼り付けるとき、先に確定させる方法。案は、`GetActiveComposition` で未確定の文字があるときだけ Enter を送って確定させてから貼り付ける。Enter を送って確定できるかは試していない
- 画像や、ほかのアプリが遅延レンダリングで置いた形式を含むクリップボードを、元に戻せるか（試作は GDI のハンドルで持つ形式を写さない）
- 署名して Program Files に入れたアプリ（`uiAccess="true"`）なら、管理者として動くアプリにも入力できるか
- 高 DPI・複数のモニターでの音声バーの位置
