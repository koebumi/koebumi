# フェーズ 0 の試作

[docs/windows.md](../../../docs/windows.md) の「フェーズ 0: 実機で確かめる」のための試作です。製品のコードではありません。確かめたことは [docs/research/windows-phase0.md](../../../docs/research/windows-phase0.md) にまとめました。

## 動かす

.NET 9 以降の SDK が要ります。

```powershell
cd windows\spikes\Phase0
dotnet build
$exe = ".\bin\Debug\net9.0-windows10.0.19041.0\Koebumi.Phase0.exe"

& $exe offline   # キー入力を送らずにできる試験（クリップボードの履歴、管理者のアプリ、UI Automation の読み取り）
& $exe auto      # SendInput で回す試験をすべて。3〜4 分、画面とキーボードを使うので触らずに待つ
& $exe probe     # 実際のキーボードで試す常駐（下の「本人が試す」）
```

ひとつずつ試すときは `clipboard`・`uipi`・`hook`・`voicebar`・`context <アプリ>`・`paste <アプリ>` です。アプリは `notepad`・`word`・`chrome`・`chrome-ce`（contenteditable）・`edge`・`edge-ce` から選びます。`context` に `--focus` を付けると、窓を最前面にしてフォーカスのある要素から読みます。読めないアプリは `dump <窓のタイトルの一部>` で UI Automation の木を書き出します。`ime-debug <アプリ>` は、変換中に貼り付けたときの動きを 1 手ずつ読み直して見せます。

結果は画面と `%TEMP%\koebumi-phase0\results-*.txt` に書きます。

- `auto` と `probe` は、入力を受けるデスクトップが要ります。リモート デスクトップを切断したセッションや、ロックした画面では SendInput が「アクセスが拒否されました」で失敗します
- メモ帳は、ふだんのメモ帳の窓に一時ファイルのタブを開き、終わったらそのタブだけを閉じます（窓は閉じません）。Word は COM で新しい文書を作り、保存せずに閉じます（ライセンス認証された Office が要ります）。Chrome と Edge は一時のプロファイル（`%TEMP%\koebumi-phase0\*-profile`）で開くので、ふだんのブラウザーには触れません
- `uipi` はタスク マネージャー（管理者として動く）を開きます。管理者でないプロセスからは閉じられないので、終わったら手で閉じてください
- 試験でクリップボードの履歴（Win+V）に入れた項目は消し、元のクリップボードに戻します

## 本人が試す（probe）

Slack・Teams・Outlook・Gmail はアカウントの中なので、自動では試しません。`probe` を起動して、次を順に試してください。

1. 試したいアプリの入力欄をクリックする（Slack は自分あてのメッセージ、Outlook は新しいメールの本文、Gmail は返信の本文など、ほかの人に届かないところ）
2. Ctrl+Win を押す。音声バーが出て、このとき画面の文字を読む
3. 1 秒ほどしてから離す。「Koebumi テスト1: 明日の会議は4時にしてください。」を貼り付けて、入ったかを読み直す
4. 入った文は手で消す
5. 終わったら、probe のウィンドウで `q` と Enter

ログでは、画面から読んだ文字を種類（漢・あ・カ・a・0）に置き換え、敬称や挨拶だけを残します。そのまま書くときは `--unmasked` を付けます。
