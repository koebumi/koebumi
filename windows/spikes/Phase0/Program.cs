using System.Text;
using System.Windows;

namespace Koebumi.Phase0;

static class Program
{
    const string Usage = """
        Koebumi.Phase0 <コマンド>

          offline            キー入力を送らずにできる試験（クリップボード、管理者のアプリ、UI Automation の読み取り）
          auto               SendInput で回す試験をすべて（接続中のデスクトップが要る。1〜2 分、画面とキーボードを使う）
          probe [--unmasked] [--minutes N]
                             実際のキーボードで試す常駐（Slack・Teams・Outlook・Gmail・管理者のアプリなど）

          dump <窓のタイトルの一部> [--unmasked]
                             窓の UI Automation の木を書き出す（読めない理由を調べるとき）
          ime-debug <notepad|chrome|chrome-ce|edge>
                             変換中に貼り付けたときの動きを、1 手ずつ読み直して見る
          keys-debug         メモ帳で Ctrl+A・Delete・日本語入力の切り替えが効くかを、1 手ずつ見る
          clipboard | uipi | hook | voicebar
          context <notepad|word|chrome|chrome-ce|edge|edge-ce|all> [--focus]
          paste <notepad|word|chrome|chrome-ce|edge|edge-ce|all>
        """;

    static readonly string[] Apps = ["notepad", "word", "chrome", "chrome-ce", "edge", "edge-ce"];

    [STAThread]
    static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        int code = 0;
        app.Startup += async (_, _) =>
        {
            try { code = await Run(args); }
            catch (Exception e) { Console.WriteLine(e); code = 1; }
            finally { app.Shutdown(); }
        };
        app.Run();
        return code;
    }

    static async Task<int> Run(string[] args)
    {
        var cmd = args.FirstOrDefault() ?? "";
        var arg = args.Skip(1).FirstOrDefault(a => !a.StartsWith("--")) ?? "";
        bool focus = args.Contains("--focus");
        IEnumerable<string> Which(string a) => a is "all" or "" ? Apps : [a];

        Report.Line($"Koebumi phase0 {DateTime.Now:yyyy-MM-dd HH:mm:ss} / {Environment.OSVersion} / 入力を受けるデスクトップ: {(Native.HasInputDesktop() ? "あり" : "なし")}");
        switch (cmd)
        {
            case "offline":
                await OfflineTests.Clipboard();
                await OfflineTests.Uipi();
                foreach (var a in Apps) await OfflineTests.Context(a, useFocus: false);
                break;
            case "auto":
                await OfflineTests.Clipboard();
                await InputTests.Hook();
                await InputTests.VoiceBarFocus();
                foreach (var a in Apps) await InputTests.Paste(a);
                foreach (var a in Apps) await OfflineTests.Context(a, useFocus: true);
                await OfflineTests.Uipi();
                break;
            case "probe":
                var minutes = args.SkipWhile(a => a != "--minutes").Skip(1).Select(int.Parse).FirstOrDefault(15);
                await Probe.Run(args.Contains("--unmasked"), minutes);
                break;
            case "keys-debug":
                await KeysDebug();
                break;
            case "ime-debug":
                await ImeDebug(arg);
                break;
            case "dump":
                await Dump(arg, args.Contains("--unmasked"));
                break;
            case "clipboard": await OfflineTests.Clipboard(); break;
            case "uipi": await OfflineTests.Uipi(); break;
            case "hook": await InputTests.Hook(); break;
            case "voicebar": await InputTests.VoiceBarFocus(); break;
            case "context":
                foreach (var a in Which(arg)) await OfflineTests.Context(a, focus);
                break;
            case "paste":
                foreach (var a in Which(arg)) await InputTests.Paste(a);
                break;
            default:
                Console.WriteLine(Usage);
                return 2;
        }
        Report.Line($"\n失敗 {Report.Failures} 件。結果: {Report.File}");
        return Report.Failures == 0 ? 0 : 1;
    }

    static async Task Dump(string title, bool unmasked)
    {
        var hwnd = Desktop.FindWindow(w => w.Title.Contains(title, StringComparison.OrdinalIgnoreCase));
        if (hwnd == IntPtr.Zero) { Report.Line("窓が見つからない: " + title); return; }
        var lines = await Mta.Run(u =>
        {
            var list = new List<string>();
            var walker = u.A.ControlViewWalker;
            void Visit(Interop.UIAutomationClient.IUIAutomationElement e, int depth)
            {
                if (list.Count > 400 || depth > 40) return;
                var name = e.CurrentName ?? "";
                list.Add($"{new string(' ', depth * 2)}{Uia.TypeName(e.CurrentControlType)} id={e.CurrentAutomationId} class={e.CurrentClassName} name={(unmasked ? name : Mask.Apply(name))}");
                for (var c = walker.GetFirstChildElement(e); c != null; c = walker.GetNextSiblingElement(c)) Visit(c, depth + 1);
            }
            Visit(u.A.ElementFromHandle(hwnd), 0);
            return list;
        });
        foreach (var l in lines) Report.Line(l);
    }

    /// メモ帳で Ctrl+A・Delete・日本語入力の切り替えが効くかを、1 手ずつ読み直して確かめる
    static async Task KeysDebug()
    {
        using var pad = new NotepadTarget("あいうえお");
        var field = await Mta.Run(u => pad.Field(u));
        async Task Show(string step) => Report.Line($"{step}: {Report.Show(await Mta.Run(_ => Uia.AllText(field!)))} ime={Ime.IsOpenForeground()} fg={Desktop.Foreground().Process}");
        Desktop.Activate(pad.Hwnd);
        await Task.Delay(500);
        await Show("開いた");
        KeySender.Send(KeySender.Key(Native.VK_END, true), KeySender.Key(Native.VK_END, false));
        await Task.Delay(200);
        KeySender.Chord(Native.VK_CONTROL, 0x41);
        await Task.Delay(300);
        await Show("Ctrl+A（まとめて送る）");
        KeySender.Tap(Native.VK_DELETE);
        await Task.Delay(300);
        await Show("Delete");
        KeySender.TypeUnicode("かきくけこ");
        await Task.Delay(300);
        await Show("かきくけこ を打つ");
        KeySender.Send(KeySender.Key(Native.VK_CONTROL, true)); await Task.Delay(50);
        KeySender.Send(KeySender.Key(0x41, true)); KeySender.Send(KeySender.Key(0x41, false)); await Task.Delay(50);
        KeySender.Send(KeySender.Key(Native.VK_CONTROL, false)); await Task.Delay(300);
        await Show("Ctrl+A（1 キーずつ）");
        KeySender.Tap(Native.VK_BACK);
        await Task.Delay(300);
        await Show("Backspace");
        Ime.Set(true);
        await Task.Delay(400);
        await Show("IME_ON");
        KeySender.TypeKeys("kaigi");
        await Task.Delay(400);
        await Show("kaigi");
        KeySender.Tap(Native.VK_ESCAPE); KeySender.Tap(Native.VK_ESCAPE);
        await Task.Delay(300);
        await Show("Esc 2 回");
        Ime.Set(false);
        await Task.Delay(300);
        await Show("IME_OFF");
        KeySender.Chord(Native.VK_CONTROL, 0x41); KeySender.Tap(Native.VK_DELETE); KeySender.Chord(Native.VK_CONTROL, 0x53);
        await Task.Delay(500);
    }

    /// 変換中に Ctrl+V を押したとき、変換中の文字がどうなるか（Enter で確定したときと比べる）
    static async Task ImeDebug(string app)
    {
        using ITarget target = app switch
        {
            "notepad" => new NotepadTarget(""),
            "edge" => new BrowserTarget("Edge", BrowserTarget.EdgePath, "mode=textarea"),
            _ => new BrowserTarget("Chrome", BrowserTarget.ChromePath, app == "chrome-ce" ? "mode=ce" : "mode=textarea"),
        };
        var field = await Mta.Run(u => target.Field(u));
        async Task<string> Read() => Report.Show(await Mta.Run(_ => Uia.AllText(field!)));
        Desktop.Activate(target.Hwnd);
        await Task.Delay(400);
        Ime.Set(false);
        await Task.Delay(300);
        // 印の文字（A・B・C・D）は日本語入力を通さずに打ち、貼り付けた後のカーソルの位置を見る
        KeySender.TypeUnicode("A");
        await ClipboardPaste.Paste("[P1]");
        KeySender.TypeUnicode("B");
        await Task.Delay(400);
        Report.Line($"日本語入力オフ A→貼り付け→B: {await Read()}");
        Ime.Set(true);
        await Task.Delay(300);
        KeySender.TypeKeys("asita");
        await Task.Delay(500);
        Report.Line($"asita と打った（未確定）: {await Read()}");
        // 変換中の文字を UI Automation で見分けられるか（TextEditPattern.GetActiveComposition）
        var composition = await Mta.Run(_ =>
        {
            try
            {
                if (field!.GetCurrentPattern(Interop.UIAutomationClient.UIA_PatternIds.UIA_TextEditPatternId) is not Interop.UIAutomationClient.IUIAutomationTextEditPattern te) return "TextEditPattern なし";
                var r = te.GetActiveComposition();
                return r == null ? "null" : $"「{r.GetText(-1)}」";
            }
            catch (Exception e) { return "error " + e.Message; }
        });
        Report.Line($"  変換中の文字（GetActiveComposition）: {composition}");
        await ClipboardPaste.Paste("[P2]");
        await Task.Delay(300);
        Report.Line($"Ctrl+V: {await Read()}");
        KeySender.TypeUnicode("C");
        await Task.Delay(400);
        Report.Line($"C を打った: {await Read()}");
        KeySender.TypeKeys("kyou");
        await Task.Delay(400);
        KeySender.Tap(Native.VK_SPACE);
        await Task.Delay(500);
        Report.Line($"kyou を変換（候補を出している）: {await Read()}");
        await ClipboardPaste.Paste("[P3]");
        await Task.Delay(300);
        Report.Line($"Ctrl+V: {await Read()}");
        KeySender.TypeUnicode("D");
        await Task.Delay(400);
        Report.Line($"D を打った: {await Read()}");
        KeySender.Tap(Native.VK_ESCAPE); KeySender.Tap(Native.VK_ESCAPE);
        await Task.Delay(300);
        Report.Line($"Esc 2 回: {await Read()}");
        Ime.Set(false);
        if (app == "notepad")
        {
            await Mta.Run(_ => { if (field!.GetCurrentPattern(Interop.UIAutomationClient.UIA_PatternIds.UIA_ValuePatternId) is Interop.UIAutomationClient.IUIAutomationValuePattern vp) vp.SetValue(""); });
            KeySender.Chord(Native.VK_CONTROL, 0x53);
            await Task.Delay(400);
        }
    }
}
