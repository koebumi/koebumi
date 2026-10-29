using System.Diagnostics;
using Interop.UIAutomationClient;
using static Koebumi.Phase0.Native;

namespace Koebumi.Phase0;

/// SendInput でキーを送る試験。入力を受けるデスクトップが要る（リモート デスクトップなら接続している間だけ動く）
static class InputTests
{
    static bool RequireInputDesktop()
    {
        if (HasInputDesktop()) return true;
        Report.Check("入力を受けるデスクトップがある", false, "リモート デスクトップを切断している・画面がロックされている");
        return false;
    }

    record Step(ushort Vk, bool Down, int WaitMs = 60);

    record Scenario(string Name, ShortcutKind Kind, WinStrategy Strategy, Step[] Steps, string Expect, bool ImeOn = false);

    static Step[] Seq(params (ushort vk, bool down)[] keys) => keys.Select(k => new Step(k.vk, k.down)).ToArray();

    static string Keys(IEnumerable<(int Msg, int Vk)> received) => string.Join(" ", received.Select(r =>
        HookEvent.KeyName(r.Vk switch { VK_CONTROL => VK_LCONTROL, _ => (ushort)r.Vk }) + (r.Msg is WM_KEYDOWN or WM_SYSKEYDOWN ? "↓" : "↑")));

    // MARK: - 1. キーボードフック

    public static async Task Hook()
    {
        Report.Head("1. キーボードフック（SendInput で押したことにする）");
        if (!RequireInputDesktop()) return;
        var clock = Stopwatch.StartNew();
        var win = new KeyLogWindow(clock);
        win.Show();
        await Task.Delay(400);
        using var hook = new KeyboardHook();
        if (!hook.Start()) { Report.Check("フックを入れる", false); win.Close(); return; }
        int on = 0, off = 0;
        hook.ShortcutChanged += (pressed, _) => { if (pressed) Interlocked.Increment(ref on); else Interlocked.Increment(ref off); };

        const ushort C = VK_LCONTROL, W = VK_LWIN;
        var scenarios = new List<Scenario>
        {
            new("対照: Win だけを押して離す", ShortcutKind.CtrlWin, WinStrategy.Auto, Seq((W, true), (W, false)), "start"),
            new("Ctrl↓ Win↓ Win↑ Ctrl↑", ShortcutKind.CtrlWin, WinStrategy.Auto, Seq((C, true), (W, true), (W, false), (C, false)), "ok"),
            new("Ctrl↓ Win↓ Ctrl↑ Win↑", ShortcutKind.CtrlWin, WinStrategy.Auto, Seq((C, true), (W, true), (C, false), (W, false)), "ok"),
            new("Win↓ Ctrl↓ Ctrl↑ Win↑", ShortcutKind.CtrlWin, WinStrategy.Auto, Seq((W, true), (C, true), (C, false), (W, false)), "ok"),
            new("Win↓ Ctrl↓ Win↑ Ctrl↑", ShortcutKind.CtrlWin, WinStrategy.Auto, Seq((W, true), (C, true), (W, false), (C, false)), "ok"),
            new("右 Win: Ctrl↓ RWin↓ RWin↑ Ctrl↑", ShortcutKind.CtrlWin, WinStrategy.Auto, Seq((C, true), (VK_RWIN, true), (VK_RWIN, false), (C, false)), "ok"),
            new("比較: 飲み込まない Ctrl↓ Win↓ Win↑ Ctrl↑", ShortcutKind.CtrlWin, WinStrategy.None, Seq((C, true), (W, true), (W, false), (C, false)), "info"),
            new("比較: 飲み込まない Win↓ Ctrl↓ Ctrl↑ Win↑", ShortcutKind.CtrlWin, WinStrategy.None, Seq((W, true), (C, true), (C, false), (W, false)), "info"),
            new("比較: マスクだけ Ctrl↓ Win↓ Win↑ Ctrl↑", ShortcutKind.CtrlWin, WinStrategy.MaskOnly, Seq((C, true), (W, true), (W, false), (C, false)), "ok"),
            new("長押し: Ctrl↓ Win↓（1.5 秒）Win↑ Ctrl↑", ShortcutKind.CtrlWin, WinStrategy.Auto,
                [new(C, true), new(W, true, 1500), new(W, false), new(C, false)], "ok"),
            new("右 Ctrl だけ", ShortcutKind.RightCtrl, WinStrategy.Auto, Seq((VK_RCONTROL, true), (VK_RCONTROL, false)), "ok"),
            new("無変換だけ（日本語入力オン）", ShortcutKind.NonConvert, WinStrategy.Auto, Seq((VK_NONCONVERT, true), (VK_NONCONVERT, false)), "ok", ImeOn: true),
        };

        foreach (var s in scenarios)
        {
            hook.Kind = s.Kind;
            hook.Strategy = s.Strategy;
            hook.ResetState();
            on = off = 0;
            if (!Desktop.Activate(win.Handle)) { Report.Check($"{s.Name}: 試験の窓を前面にする", false, Desktop.Foreground().Process); continue; }
            win.Box.Focus();
            await Task.Delay(200);
            bool? imeBefore = null;
            if (s.ImeOn)
            {
                Ime.Set(true);
                await Task.Delay(400);
                imeBefore = Ime.IsOpenForeground();
            }
            win.Received.Clear();

            foreach (var step in s.Steps)
            {
                KeySender.Send(KeySender.Key(step.Vk, step.Down, marked: false));
                await Task.Delay(step.WaitMs);
            }
            await Task.Delay(800);
            bool start = Desktop.StartMenuIsForeground();
            var fg = Desktop.Foreground();
            var received = win.Received.Select(r => (r.Msg, r.Vk)).ToList();
            var events = hook.Events.ToArray();
            bool? imeAfter = s.ImeOn ? Ime.IsOpenForeground() : null;

            string detail = $"on={on} off={off} スタート={(start ? "開いた" : "開かない")} 前面={fg.Process}"
                + $" / 窓に届いたキー: {(received.Count == 0 ? "なし" : Keys(received))}"
                + (s.ImeOn ? $" / 日本語入力 {imeBefore}→{imeAfter}" : "");
            switch (s.Expect)
            {
                case "start":
                    Report.Check(s.Name + "（スタートメニューが開くはず。開かなければ、この試験は SendInput では確かめられない）", start, detail);
                    break;
                case "info":
                    Report.Info(s.Name, detail);
                    break;
                default:
                    bool swallowedOk = s.Kind switch
                    {
                        ShortcutKind.RightCtrl => received.All(r => r.Vk != VK_CONTROL),
                        ShortcutKind.NonConvert => received.All(r => r.Vk != VK_NONCONVERT) && imeAfter == imeBefore,
                        _ => true,
                    };
                    Report.Check(s.Name, on == 1 && off == 1 && !start && swallowedOk, detail);
                    break;
            }
            Report.Line("     フック: " + string.Join(" | ", events.Select(e => e.ToString().Trim())));

            if (start || fg.Hwnd != win.Handle)
            {
                KeySender.Tap(VK_ESCAPE);
                await Task.Delay(500);
            }
            if (s.ImeOn) Ime.Set(false);
        }

        bool stuck = new[] { VK_LWIN, VK_RWIN, VK_LCONTROL, VK_RCONTROL }.Any(vk => (GetAsyncKeyState(vk) & 0x8000) != 0);
        Report.Check("押されたままのキーが残らない", !stuck);
        Report.Info("フックのコールバックにかかった最長の時間", $"{hook.MaxCallbackMs:F2} ms");
        win.Close();
    }

    // MARK: - 2. 音声バー

    public static async Task VoiceBarFocus()
    {
        Report.Head("2. 音声バーでフォーカスが外れないか（メモ帳）");
        if (!RequireInputDesktop()) return;
        using var pad = new NotepadTarget("");
        if (pad.Hwnd == IntPtr.Zero) { Report.Check("メモ帳を開く", false); return; }
        var field = await Mta.Run(u => pad.Field(u));
        GetCursorPos(out var mouse);

        foreach (var style in new[] { VoiceBar.BarStyle.NoActivate, VoiceBar.BarStyle.ShowNotActivated, VoiceBar.BarStyle.Default })
        {
            Report.Line($"  -- {style}{(style == VoiceBar.BarStyle.NoActivate ? "（案）" : "（比べるため）")}");
            // 案だけを合否にし、ほかは結果を記録する
            void Expect(string item, bool ok, string detail = "")
            {
                if (style == VoiceBar.BarStyle.NoActivate) Report.Check(item, ok, detail);
                else Report.Info(item, (ok ? "はい" : "いいえ") + (detail.Length > 0 ? " " + detail : ""));
            }
            if (!Desktop.Activate(pad.Hwnd)) { Report.Check("メモ帳を前面にする", false); continue; }
            await Task.Delay(300);
            var focus0 = await Mta.Run(u => u.A.GetFocusedElement()?.GetRuntimeId() as int[]);

            var bar = new VoiceBar(style);
            bar.Show();
            await Task.Delay(300);
            var fg1 = GetForegroundWindow();
            var focus1 = await Mta.Run(u => u.A.GetFocusedElement()?.GetRuntimeId() as int[]);
            Expect("出したあとも最前面はメモ帳", fg1 == pad.Hwnd, Desktop.Describe(fg1).Process);
            Expect("出したあともフォーカスは同じ入力欄", focus0 != null && focus1 != null && focus0.SequenceEqual(focus1));

            var rnd = new Random(1);
            for (int i = 0; i < 20; i++)
            {
                bar.SetLevel(rnd.NextDouble());
                bar.SetText(i % 2 == 0 ? "録音中" : "録音中…");
                await Task.Delay(50);
            }
            Expect("音量の表示を動かしても最前面はメモ帳", GetForegroundWindow() == pad.Hwnd);

            var marker = style switch { VoiceBar.BarStyle.NoActivate => "あ", VoiceBar.BarStyle.ShowNotActivated => "い", _ => "う" };
            KeySender.TypeUnicode(marker);
            await Task.Delay(300);
            var text = field == null ? null : await Mta.Run(_ => Uia.AllText(field));
            Expect("出している間に打った文字がメモ帳に入る", text?.Contains(marker) == true, Report.Show(text));

            var (x, y) = bar.CancelButtonCenter();
            KeySender.Click(x, y);
            await Task.Delay(400);
            var fg2 = GetForegroundWindow();
            Expect("バーの「×」を押しても最前面はメモ帳", fg2 == pad.Hwnd, Desktop.Describe(fg2).Process);
            Report.Info("「×」のクリックが届いた回数", bar.CancelClicks.ToString());

            bar.Hide();
            await Task.Delay(150);
            bar.Show();
            await Task.Delay(300);
            Expect("隠して出し直しても最前面はメモ帳", GetForegroundWindow() == pad.Hwnd);
            bar.Close();
        }
        SetCursorPos(mouse.X, mouse.Y);
        // 打った文字を消して保存し、保存の確認なしで閉じられるようにする
        if (Desktop.Activate(pad.Hwnd))
        {
            KeySender.Chord(VK_CONTROL, 0x41 /* A */);
            KeySender.Tap(VK_DELETE);
            KeySender.Chord(VK_CONTROL, 0x53 /* S */);
            await Task.Delay(400);
        }
    }

    // MARK: - 3. 貼り付け

    public const string PasteText = "明日の会議は4時にしてください。Claude Code 🙂";

    public static async Task Paste(string app)
    {
        Report.Head($"3. Ctrl+V の貼り付け: {app}");
        if (!RequireInputDesktop()) return;
        ITarget? target = null;
        var user = ClipboardPaste.Snapshot();
        try
        {
            target = app switch
            {
                "notepad" => new NotepadTarget(""),
                "word" => new WordTarget("", 0),
                "chrome" => new BrowserTarget("Chrome", BrowserTarget.ChromePath, "mode=textarea"),
                "chrome-ce" => new BrowserTarget("Chrome", BrowserTarget.ChromePath, "mode=ce"),
                "edge" => new BrowserTarget("Edge", BrowserTarget.EdgePath, "mode=textarea"),
                "edge-ce" => new BrowserTarget("Edge", BrowserTarget.EdgePath, "mode=ce"),
                _ => throw new ArgumentException(app),
            };
            if (target.Hwnd == IntPtr.Zero) { Report.Check($"{app} を開く", false); return; }
            // ライセンス認証されていない Office は編集できず、認証の画面が COM の呼び出しを止める
            var title = Desktop.Describe(target.Hwnd).Title;
            if (title.Contains("ライセンス認証") || title.Contains("Unlicensed")) { Report.Info($"{app} を飛ばした", title); return; }
            var t = target;
            var field = await Mta.Run(u => t.Field(u));
            if (field == null) { Report.Check("入力欄の要素を見つける", false); return; }
            Func<Task<string>> read = async () => Report.Lines(await Mta.Run(_ => Uia.AllText(field)) ?? "");
            // 入力欄を空にする。文字を打った後の Ctrl+A がメモ帳で効かないことがあったので、UI Automation（Word は COM）で消す
            async Task<bool> Clear()
            {
                if (t is WordTarget w) w.Text = "";
                else await Mta.Run(_ =>
                {
                    if (field.GetCurrentPattern(UIA_PatternIds.UIA_ValuePatternId) is IUIAutomationValuePattern vp && vp.CurrentIsReadOnly == 0) vp.SetValue("");
                });
                await Task.Delay(200);
                if ((await read()).Trim().Length > 0)
                {
                    KeySender.Chord(VK_CONTROL, VK_END);
                    KeySender.Send(KeySender.Key(VK_CONTROL, true), KeySender.Key(VK_SHIFT, true), KeySender.Key(VK_HOME, true), KeySender.Key(VK_HOME, false),
                        KeySender.Key(VK_SHIFT, false), KeySender.Key(VK_CONTROL, false));
                    KeySender.Tap(VK_DELETE);
                    await Task.Delay(200);
                }
                return (await read()).Trim().Length == 0;
            }

            foreach (var mode in new[] { "日本語入力オフ", "日本語入力オン", "変換中（kaigi と打った後）" })
            {
                if (!Desktop.Activate(target.Hwnd)) { Report.Check($"{mode}: 前面にする", false); continue; }
                await Task.Delay(300);
                if (!await Clear()) Report.Info($"{mode}: 入力欄を空にできない", Report.Show(await read()));
                var ime = Ime.Set(mode != "日本語入力オフ");
                if (mode.StartsWith("変換中"))
                {
                    KeySender.TypeKeys("kaigi");
                    await Task.Delay(400);
                }
                var composing = await read();

                var original = $"koebumi-phase0 元 {Guid.NewGuid():N}"[..28];
                ClipboardPaste.SetText(original, excludeFromHistory: true);
                var sw = Stopwatch.StartNew();
                var pasteTask = ClipboardPaste.Paste(PasteText);
                string now = "";
                double appeared = -1;
                while (sw.ElapsedMilliseconds < 1500)
                {
                    now = await read();
                    if (now.Contains(PasteText)) { appeared = sw.Elapsed.TotalMilliseconds; break; }
                    await Task.Delay(30);
                }
                var result = await pasteTask;
                await Task.Delay(300);
                var final = await read();
                var restored = ClipboardPaste.GetText();
                Report.Check($"{mode}: 入る", final.Contains(PasteText),
                    $"日本語入力={ime} 貼り付け前={Report.Show(composing)} 後={Report.Show(final)} 入るまで {appeared:F0} ms 送ったキー {result.Sent} {result.Note}");
                Report.Check($"{mode}: 元のクリップボードに戻る", restored == original && result.Restored);
                if (mode.StartsWith("変換中"))
                {
                    KeySender.Tap(VK_ESCAPE);
                    KeySender.Tap(VK_ESCAPE);
                    await Task.Delay(300);
                    Report.Info($"{mode}: Esc を 2 回押した後", Report.Show(await read()));
                }
            }
            var history = await ClipboardPaste.History(PasteText);
            Report.Check("貼り付けた文がクリップボードの履歴に残らない", history.Matches == 0, $"{history.Status} {history.Matches} 件");

            Ime.Set(false);
            if (Desktop.Activate(target.Hwnd))
            {
                await Clear();
                if (app == "notepad") KeySender.Chord(VK_CONTROL, 0x53 /* S */);
                await Task.Delay(400);
            }
        }
        catch (Exception e) { Report.Check($"{app} の試験", false, e.Message); }
        finally
        {
            target?.Dispose();
            await ClipboardPaste.DeleteFromHistory("koebumi-phase0");
            ClipboardPaste.Restore(user, excludeFromHistory: true);
        }
    }

    // MARK: - 5. 管理者として動くアプリ

    public static async Task UipiInput(IntPtr tm)
    {
        var win = new KeyLogWindow(Stopwatch.StartNew());
        win.Show();
        await Task.Delay(300);
        var seen = new List<(string Process, bool Elevated)>();
        WinEventProc proc = (_, _, hwnd, _, _, _, _) =>
        {
            GetWindowThreadProcessId(hwnd, out var pid);
            seen.Add((Desktop.ProcessName(pid), Elevation.IsAboveSelf(pid)));
        };
        var weHook = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, IntPtr.Zero, proc, 0, 0, WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
        using var hook = new KeyboardHook();
        hook.Start();
        try
        {
            Desktop.Activate(win.Handle);
            await Task.Delay(300);
            bool activated = Desktop.Activate(tm);
            await Task.Delay(500);
            Report.Check("タスク マネージャーを前面にできる", activated);
            Report.Check("前面が管理者のアプリに変わったと、窓のイベントでわかる（ここで知らせられる）",
                seen.Any(s => s.Elevated), string.Join(", ", seen.Select(s => $"{s.Process}{(s.Elevated ? "(管理者)" : "")}")));

            hook.ResetState();
            var sent = KeySender.Send(KeySender.Key(VK_LCONTROL, true, false), KeySender.Key(VK_LWIN, true, false));
            var err = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
            await Task.Delay(100);
            KeySender.Send(KeySender.Key(VK_LWIN, false, false), KeySender.Key(VK_LCONTROL, false, false));
            await Task.Delay(300);
            Report.Info("前面が管理者のアプリのとき SendInput で Ctrl+Win", $"送れた数 {sent} err={err} フックが受けたキー {hook.Events.Count} 個 スタート={(Desktop.StartMenuIsForeground() ? "開いた" : "開かない")}");
            if (Desktop.StartMenuIsForeground()) { KeySender.Tap(VK_ESCAPE); await Task.Delay(300); }

            var p = await ClipboardPaste.Paste("koebumi-phase0 uipi");
            Report.Info("前面が管理者のアプリのとき Ctrl+V", $"送れた数 {p.Sent} err={System.Runtime.InteropServices.Marshal.GetLastWin32Error()}");
        }
        finally
        {
            UnhookWinEvent(weHook);
            GC.KeepAlive(proc);
            Desktop.Activate(win.Handle);
            win.Close();
        }
    }
}
