using System.Diagnostics;
using Interop.UIAutomationClient;
using static Koebumi.Phase0.Native;

namespace Koebumi.Phase0;

/// UI Automation は MTA のスレッドで使う
static class Mta
{
    static Uia? shared;
    public static Task<T> Run<T>(Func<Uia, T> f) => Task.Run(() => f(shared ??= new Uia()));
    public static Task Run(Action<Uia> f) => Task.Run(() => f(shared ??= new Uia()));
}

/// キー入力を送らずにできる試験（リモート デスクトップを切断していても動く）
static class OfflineTests
{
    // MARK: - クリップボードの履歴

    /// 貼り付けに使った文と、元に戻した内容が、クリップボードの履歴（Win+V）に残らないか
    public static async Task Clipboard()
    {
        Report.Head("クリップボードの履歴に残さない形式");
        var user = ClipboardPaste.Snapshot();
        var id = Guid.NewGuid().ToString("N")[..8];
        var original = $"koebumi-phase0 元の内容 {id}";
        var pasted = $"koebumi-phase0 貼り付け {id}";
        var control = $"koebumi-phase0 対照 {id}";
        try
        {
            ClipboardPaste.SetText(original, excludeFromHistory: false);
            await Task.Delay(1000);
            var h0 = await ClipboardPaste.History(original);
            Report.Info("履歴", $"enabled={h0.Enabled} status={h0.Status} items={h0.Items}");
            if (!h0.Enabled || h0.Status != "ok") { Report.Check("履歴を読める", false, h0.Status); return; }
            Report.Check("ふつうに入れた元の内容は履歴に入る", h0.Matches == 1, $"{h0.Matches} 件");

            // 貼り付けの流れ（Ctrl+V は送らない）
            var saved = ClipboardPaste.Snapshot();
            ClipboardPaste.SetText(pasted, excludeFromHistory: true);
            await Task.Delay(1000);
            var h1 = await ClipboardPaste.History(pasted);
            Report.Check("履歴に残さない形式を付けた文は履歴に入らない", h1.Matches == 0, $"{h1.Matches} 件");
            Report.Check("その文はクリップボードには入っている", ClipboardPaste.GetText() == pasted);

            ClipboardPaste.Restore(saved, excludeFromHistory: true);
            await Task.Delay(1000);
            var h2 = await ClipboardPaste.History(original);
            Report.Check("元の内容に戻せる", ClipboardPaste.GetText() == original, Report.Show(ClipboardPaste.GetText()));
            Report.Check("戻すときに形式を付ければ、履歴に同じ項目が増えない", h2.Matches == 1, $"{h2.Matches} 件");

            // 比べるため、形式を付けずに戻す
            ClipboardPaste.SetText(pasted, excludeFromHistory: true);
            ClipboardPaste.Restore(saved, excludeFromHistory: false);
            await Task.Delay(1000);
            var h3 = await ClipboardPaste.History(original);
            Report.Info("形式を付けずに戻したときの履歴の件数", $"{h3.Matches} 件（2 件なら、戻すたびに履歴が増える）");

            ClipboardPaste.SetText(control, excludeFromHistory: false);
            await Task.Delay(1000);
            var h4 = await ClipboardPaste.History(control);
            Report.Check("対照: 形式を付けない文は履歴に入る（読み方の確認）", h4.Matches == 1, $"{h4.Matches} 件");
        }
        finally
        {
            var deleted = await ClipboardPaste.DeleteFromHistory("koebumi-phase0");
            ClipboardPaste.Restore(user, excludeFromHistory: true);
            Report.Info("後片付け", $"試験で履歴に入った {deleted} 件を消し、元のクリップボードに戻した（{user.Count} 形式）");
        }
    }

    // MARK: - 管理者として動くアプリ

    public static async Task Uipi()
    {
        Report.Head("管理者として動くアプリ（UIPI）");
        var self = Elevation.Self();
        Report.Info("自分", $"elevated={self.Elevated} integrity={Elevation.Name(self.Integrity)}");

        var elevated = new List<string>();
        EnumWindows((h, _) =>
        {
            if (!IsWindowVisible(h) || WindowText(h).Length == 0) return true;
            GetWindowThreadProcessId(h, out var pid);
            var level = Elevation.Of(pid);
            if (level.Known && level.Integrity > self.Integrity) elevated.Add($"{Desktop.ProcessName(pid)} ({Elevation.Name(level.Integrity)})");
            if (!level.Known && pid != 0) elevated.Add($"pid {pid}: {level.Error}");
            return true;
        }, IntPtr.Zero);
        Report.Info("いま開いている、自分より上の窓", elevated.Count == 0 ? "なし" : string.Join(", ", elevated.Distinct()));

        // タスク マネージャーは、管理者のアカウントなら確認なしで管理者として起動する
        bool started = false;
        var tm = Desktop.FindWindow(w => w.Process.Equals("Taskmgr.exe", StringComparison.OrdinalIgnoreCase));
        if (tm == IntPtr.Zero)
        {
            Process.Start(new ProcessStartInfo("taskmgr.exe") { UseShellExecute = true });
            tm = Desktop.WaitForWindow(w => w.Process.Equals("Taskmgr.exe", StringComparison.OrdinalIgnoreCase), 8000);
            started = true;
        }
        if (tm == IntPtr.Zero)
        {
            // 管理者として動くプロセスの名前は、低い整合性レベルからでも取れるとは限らない
            tm = Desktop.WaitForWindow(w => w.Title.Contains("タスク マネージャー") || w.Title.Contains("Task Manager"), 3000);
        }
        if (tm == IntPtr.Zero) { Report.Check("タスク マネージャーの窓を見つける", false); return; }
        GetWindowThreadProcessId(tm, out var tmPid);
        var tmLevel = Elevation.Of(tmPid);
        // UIPI は整合性レベルで決まるので、自分より上かどうかで見分ける
        Report.Check("タスク マネージャーが自分より上の整合性レベルで動いているとわかる", tmLevel.Known && tmLevel.Integrity > self.Integrity,
            $"known={tmLevel.Known} elevated={tmLevel.Elevated} integrity={Elevation.Name(tmLevel.Integrity)} {tmLevel.Error}");

        var uiaInfo = await Mta.Run(u =>
        {
            try
            {
                var e = u.A.ElementFromHandle(tm);
                var all = e.FindAll(TreeScope.TreeScope_Descendants, u.A.CreateTrueCondition());
                return $"要素 {all.Length} 個 / {u.Describe(e)}";
            }
            catch (Exception ex) { return "読めない: " + ex.Message; }
        });
        Report.Info("UI Automation でタスク マネージャーを読む", uiaInfo);

        if (HasInputDesktop()) await InputTests.UipiInput(tm);
        else Report.Info("入力の試験", "入力を受けるデスクトップがないので飛ばした（リモート デスクトップを切断中）");

        if (started)
        {
            bool posted = PostMessage(tm, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
            var err = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
            await Task.Delay(800);
            Report.Info("タスク マネージャーを WM_CLOSE で閉じる", $"posted={posted} err={err} 残っている={IsWindow(tm)}");
        }
    }

    // MARK: - UI Automation の読み取り

    public const string Before = "東海林さん、お疲れ様です。\n明日の会議の件で";
    public const string After = "よろしくお願いします。";

    public static async Task Context(string app, bool useFocus)
    {
        Report.Head($"UI Automation の読み取り: {app}（{(useFocus ? "フォーカスから" : "要素を探して")}）");
        ITarget? target = null;
        try
        {
            target = app switch
            {
                "notepad" => new NotepadTarget(Before + After),
                "word" => new WordTarget(Before + After, Before.Length),
                "chrome" => new BrowserTarget("Chrome", BrowserTarget.ChromePath, "mode=textarea&text=context"),
                "chrome-ce" => new BrowserTarget("Chrome", BrowserTarget.ChromePath, "mode=ce&text=context"),
                "edge" => new BrowserTarget("Edge", BrowserTarget.EdgePath, "mode=textarea&text=context"),
                "edge-ce" => new BrowserTarget("Edge", BrowserTarget.EdgePath, "mode=ce&text=context"),
                _ => throw new ArgumentException(app),
            };
            if (target.Hwnd == IntPtr.Zero) { Report.Check($"{app} の窓を開く", false); return; }

            if (useFocus)
            {
                Report.Check("最前面にする", Desktop.Activate(target.Hwnd));
                await Task.Delay(500);
            }

            var t = target;
            var sw = Stopwatch.StartNew();
            var field = useFocus ? null : await Mta.Run(u => t.Field(u));
            var findMs = sw.Elapsed.TotalMilliseconds;
            if (!useFocus && field == null) { Report.Check("入力欄の要素を見つける", false); return; }
            if (!useFocus) Report.Info("入力欄の要素を探す時間（試験のためだけ）", $"{findMs:F0} ms");
            if (target is BrowserTarget b && !useFocus) Report.Info("Chromium がアクセシビリティの木を出すまで待った時間", $"{b.FieldWaitMs:F0} ms");

            // メモ帳はファイルを開いた直後のカーソルが先頭にあるので、UI Automation で動かす（AI の整形を戻す機能でも使う）
            if (app == "notepad")
            {
                var f = field ?? await Mta.Run(u => u.A.GetFocusedElement());
                var placed = await Mta.Run(_ => Uia.PlaceCaret(f, Before.Length));
                Report.Info("UI Automation でカーソルを置く（TextRange.Select）", placed ? "呼べた" : "TextPattern がない");
                await Task.Delay(200);
            }

            for (int i = 0; i < 3; i++)
            {
                bool walk = i == 2;
                var r = await Mta.Run(u => u.Read(field, useFocus ? IntPtr.Zero : t.Hwnd, includeScreen: true, walk: walk));
                var label = i == 0 ? "1 回目" : i == 1 ? "2 回目" : "3 回目（1 段ずつたどる）";
                if (r.Error.Length > 0) { Report.Check($"{label} 読める", false, r.Error + " / " + r.Focus); continue; }
                var s = r.Text!;
                // 入力欄の中の文字だけを読めたか（ページのほかの文字が混ざらないか）
                bool beforeOk = Report.Lines(s.Before).Trim() == Report.Lines(Before);
                bool afterOk = Report.Lines(s.After).Trim() == After;
                Report.Check($"{label} カーソルの前", beforeOk, Report.Show(s.Before));
                Report.Check($"{label} カーソルの後", afterOk, Report.Show(Mask.Short(s.After)));
                bool timeOk = r.TotalMs <= 300;
                Report.Check($"{label} 0.3 秒以内", timeOk,
                    $"計 {r.TotalMs:F0} ms（フォーカス {r.FocusMs:F0} / カーソル前後 {r.CaretMs:F0} / ウィンドウ {r.ScreenMs:F0} ms, 要素 {r.Nodes} 個） {r.Method}");
                Report.Info($"{label} ウィンドウの文字（入力欄の前）", Mask.Short(Report.Show(s.Screen), 160));
                Report.Info($"{label} ウィンドウの文字（入力欄の後）", Mask.Short(Report.Show(s.ScreenAfter), 160));
                if (i == 0) Report.Info("フォーカスのある要素", r.Focus);
            }
        }
        catch (Exception e) { Report.Check($"{app} の試験", false, e.Message); }
        finally
        {
            // Word の COM は作ったスレッドで閉じる
            target?.Dispose();
        }
    }
}
