using System.Diagnostics;
using System.Text;
using System.Windows;
using static Koebumi.Phase0.Native;

namespace Koebumi.Phase0;

/// 人が実際のキーボードで試すための常駐。Ctrl+Win を押すと画面の文字を読み、離すと試験の文を貼り付けて、入ったかを読み直す。
/// 結果は %TEMP%\koebumi-phase0\results-*.txt に書く。画面の文字は種類に置き換えて書く（--unmasked でそのまま）
static class Probe
{
    public static async Task Run(bool unmasked, int minutes)
    {
        Report.Head("確認用の常駐（Ctrl+Win を押している間だけ録音中のつもり）");
        if (!HasInputDesktop()) { Report.Check("入力を受けるデスクトップがある", false, "リモート デスクトップを切断している・画面がロックされている"); return; }
        Report.Line("""
            使い方:
              1. 試したいアプリの入力欄をクリックする
              2. Ctrl+Win を押す（音声バーが出る。このとき画面の文字を読む）
              3. 1 秒ほどしてから離す（試験の文を貼り付けて、入ったかを確かめる）
              4. 終わったら、このウィンドウで q と Enter を押す
            管理者として動くアプリ（タスク マネージャーなど）に切り替えると、音声バーでそのことを知らせる。
            """);

        string Text(string s) => unmasked ? Report.Show(s) : Mask.Apply(Report.Show(s));
        var dispatcher = Application.Current.Dispatcher;
        var bar = new VoiceBar(VoiceBar.BarStyle.NoActivate);
        using var hook = new KeyboardHook { Kind = ShortcutKind.CtrlWin, Strategy = WinStrategy.Auto };
        int count = 0;
        var allEvents = new List<HookEvent>();
        Desktop.Info? target = null;
        var pressedAt = Stopwatch.StartNew();

        async Task OnPress()
        {
            count++;
            pressedAt.Restart();
            target = Desktop.Foreground();
            var level = Elevation.Of(target.Pid);
            Report.Line($"\n-- {count} 回目: {target.Process} 「{Text(target.Title)}」 整合性={Elevation.Name(level.Integrity)}");
            bar.SetText("読み取り中…");
            bar.Show();
            var r = await Mta.Run(u => u.Read());
            bar.SetText("録音中（離すと貼り付け）");
            var fg = GetForegroundWindow();
            Report.Check("音声バーを出しても最前面が変わらない", fg == target.Hwnd, Desktop.Describe(fg).Process);
            if (r.Error.Length > 0) { Report.Check("画面の文字を読む", false, r.Error); return; }
            Report.Check("0.3 秒以内に読める", r.TotalMs <= 300,
                $"計 {r.TotalMs:F0} ms（フォーカス {r.FocusMs:F0} / カーソル前後 {r.CaretMs:F0} / ウィンドウ {r.ScreenMs:F0} ms, 要素 {r.Nodes} 個） {r.Method}");
            Report.Info("フォーカスのある要素", r.Focus);
            if (r.Text is { } s)
            {
                Report.Info("カーソルの前", $"{s.Before.Length} 字 {Mask.Short(Text(s.Before), 120)}");
                Report.Info("カーソルの後", $"{s.After.Length} 字 {Mask.Short(Text(s.After), 120)}");
                Report.Info("ウィンドウ（入力欄の前）", $"{s.Screen.Length} 字 {Mask.Short(Text(s.Screen), 160)}");
                Report.Info("ウィンドウ（入力欄の後）", $"{s.ScreenAfter.Length} 字 {Mask.Short(Text(s.ScreenAfter), 160)}");
            }
        }

        async Task OnRelease()
        {
            bar.Hide();
            await Task.Delay(150);
            Report.Check("離したあとにスタートメニューが開かない", !Desktop.StartMenuIsForeground());
            if (Desktop.StartMenuIsForeground()) { KeySender.Tap(VK_ESCAPE); await Task.Delay(300); }
            if (target == null) return;
            if (Elevation.IsAboveSelf(target.Pid)) Report.Info("貼り付け", "管理者のアプリなので届かないはず");
            // Win を先に押したときは Win を飲み込めないので、すべて離すまで待つ（Win+Ctrl+V は音の出力の切り替えになる）
            var wait = Stopwatch.StartNew();
            ushort[] mods = [VK_LWIN, VK_RWIN, VK_LCONTROL, VK_RCONTROL, VK_LSHIFT, VK_RSHIFT, VK_LMENU, VK_RMENU];
            while (wait.ElapsedMilliseconds < 3000 && mods.Any(vk => (GetAsyncKeyState(vk) & 0x8000) != 0)) await Task.Delay(30);
            var text = $"Koebumi テスト{count}: 明日の会議は4時にしてください。";
            var p = await ClipboardPaste.Paste(text);
            await Task.Delay(200);
            var r = await Mta.Run(u => u.Read(includeScreen: false));
            var before = Report.Lines(r.Text?.Before);
            bool pasted = before.EndsWith(text);
            Report.Check("貼り付けた文がカーソルの前にある（UI Automation で読み直す）", pasted,
                pasted ? "" : $"読めた前の文字: {Mask.Short(Text(before), 120)} {r.Error}");
            Report.Info("クリップボード", $"元に戻した={p.Restored}（{p.SavedFormats} 形式） {p.Note}");
            var h = await ClipboardPaste.History(text);
            Report.Check("貼り付けた文が履歴（Win+V）に残らない", h.Matches == 0, $"{h.Status} {h.Matches} 件");
        }

        hook.ShortcutChanged += (pressed, _) => dispatcher.BeginInvoke(async () =>
        {
            try { if (pressed) await OnPress(); else await OnRelease(); }
            catch (Exception e) { Report.Check("試験", false, e.Message); }
        });
        if (!hook.Start()) { Report.Check("フックを入れる", false); return; }

        // Ctrl・Win キーがフックに届いたかを、前面のアプリと一緒に書く（Ctrl+Win が効かなかったときに理由を探すため）
        var keyLog = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(300) };
        keyLog.Tick += (_, _) =>
        {
            var lines = new List<string>();
            while (hook.Events.TryDequeue(out var e))
            {
                allEvents.Add(e);
                if (!e.Marked && e.Vk is VK_LCONTROL or VK_RCONTROL or VK_LWIN or VK_RWIN) lines.Add(e.ToString().Trim());
            }
            if (lines.Count > 0) Report.Line($"     キー（前面 {Desktop.Foreground().Process}）: {string.Join(" | ", lines)}");
        };
        keyLog.Start();

        // 管理者として動くアプリに切り替わったら知らせる（そのアプリの前ではフックにキーが届かない）
        WinEventProc proc = (_, _, hwnd, _, _, _, _) =>
        {
            GetWindowThreadProcessId(hwnd, out var pid);
            Report.Line($"     前面: {Desktop.ProcessName(pid)}");
            if (!Elevation.IsAboveSelf(pid)) return;
            Report.Info("管理者のアプリが前面になった", Desktop.ProcessName(pid));
            bar.SetText("管理者として動いているアプリには入力できません");
            bar.Show();
            _ = Task.Delay(2500).ContinueWith(_ => dispatcher.BeginInvoke(() => bar.Hide()));
        };
        var weHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, IntPtr.Zero, proc, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);

        var quit = new TaskCompletionSource();
        _ = Task.Run(() =>
        {
            while (Console.ReadLine() is { } line && line.Trim() != "q") { }
            quit.TrySetResult();
        });
        await Task.WhenAny(quit.Task, Task.Delay(TimeSpan.FromMinutes(minutes)));

        keyLog.Stop();
        while (hook.Events.TryDequeue(out var rest)) allEvents.Add(rest);
        UnhookWinEvent(weHook);
        GC.KeepAlive(proc);
        bar.Close();
        await ClipboardPaste.DeleteFromHistory("Koebumi テスト");
        // 物理キーかどうか（リモート デスクトップの入力に injected が付くか）を記録する
        var kinds = allEvents.Where(e => !e.Marked).GroupBy(e => e.Injected).Select(g => $"{(g.Key ? "injected" : "physical")} {g.Count()}");
        Report.Info("フックが受けたキー", string.Join(", ", kinds));
        Report.Info("フックのコールバックにかかった最長の時間", $"{hook.MaxCallbackMs:F2} ms");
    }
}
