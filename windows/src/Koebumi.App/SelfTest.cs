using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Koebumi.Core;
using Microsoft.Win32.SafeHandles;
using CoreAppContext = Koebumi.Core.AppContext;

namespace Koebumi.App;

/// `Koebumi.App.exe --selftest`。人の操作がなくてもできる確認を一通り動かし、結果を親のコンソールと
/// %TEMP%\koebumi-selftest.txt に書く。入力を受けるデスクトップがない（リモート デスクトップの切断・画面のロック）ときは、
/// キーを送る確認とフックの確認を飛ばす
sealed class SelfTest(App app)
{
    readonly string logPath = Path.Combine(Path.GetTempPath(), "koebumi-selftest.txt");
    readonly Action<string> console = OpenConsole();
    int passed, failed, skipped;

    public async Task<int> RunAsync()
    {
        File.WriteAllText(logPath, "");
        Write($"Koebumi selftest {DateTime.Now:yyyy-MM-dd HH:mm:ss}  {RuntimeInformation.OSDescription}  {RuntimeInformation.FrameworkDescription}");
        bool desktop = Native.HasInputDesktop();
        Write($"入力を受けるデスクトップ: {(desktop ? "あり" : "なし（SendInput とフックの確認は飛ばす）")}");

        await Step("CredentialStore", CredentialStoreTest);
        await Step("AudioDevices", AudioDevicesTest);
        await Step("JapanesePhoneticReader", JapanesePhoneticReaderTest);
        await Step("ForegroundApp", ForegroundAppTest);
        await Step("SurroundingTextReader", SurroundingTextReaderTest);
        await Step("AudioRecorder", AudioRecorderTest);
        await Step("TextInserter", TextInserterTest);
        await Step("HotkeyManager", HotkeyManagerTest);
        await Step("KeyboardHookThread / KeySender", () => HookTest(desktop));
        await Step("TrayIcon / ForegroundWatcher", ShellTest);

        Write($"結果: 成功 {passed}、失敗 {failed}、飛ばした {skipped}");
        return failed == 0 ? 0 : 1;
    }

    async Task Step(string name, Func<Task> run)
    {
        Write($"\n== {name}");
        try { await run(); }
        catch (Exception e) { Fail(name, "例外: " + e); }
    }

    // MARK: - 確認

    Task CredentialStoreTest()
    {
        var store = new CredentialStore();
        var account = "selftest-" + Guid.NewGuid().ToString("N")[..8];
        try
        {
            var secret = "テスト-" + Guid.NewGuid();
            store.Set(secret, account);
            Check("保存して読み出せる", store.Get(account) == secret);
            store.Set("", account);
            Check("空の値で消える", store.Get(account) == null);
            store.Set("", account);
            Pass("ないものを消してもエラーにならない");
        }
        finally
        {
            try { store.Set("", account); } catch (Exception) { }
        }
        return Task.CompletedTask;
    }

    Task AudioDevicesTest()
    {
        var devices = AudioDevices.Capture();
        Write($"録音デバイス {devices.Count} 個、既定の ID: {AudioDevices.DefaultId() ?? "なし"}");
        foreach (var d in devices) Write($"  {(d.IsDefault ? "*" : " ")} {d.Name}");
        if (devices.Count == 0) Skip("録音デバイスの一覧", "デバイスがない");
        else Check("既定のデバイスが先頭", devices[0].IsDefault || AudioDevices.DefaultId() == null);
        return Task.CompletedTask;
    }

    Task JapanesePhoneticReaderTest()
    {
        var reader = new JapanesePhoneticReader();
        const string sentence = "東海林さんに渡邉さんの資料を送る";
        var tokens = reader.Tokenize(sentence);
        Write("  " + string.Join(" ", tokens.Select(t => $"{t.Surface}[{t.Reading}]@{t.Start}")));
        if (reader.LastError != null) Write("  解析の失敗: " + reader.LastError);
        Check("語に分かれる", tokens.Count > 1);
        Check("位置が元の文と合う", tokens.All(t => string.CompareOrdinal(sentence, t.Start, t.Surface, 0, t.Surface.Length) == 0));
        Check("読みが付く", tokens.Any(t => t.Reading.Length > 0));

        var long_ = string.Concat(Enumerable.Repeat(sentence + "。", 120));
        var watch = Stopwatch.StartNew();
        var longTokens = reader.Tokenize(long_);
        Write($"  長い文 {long_.Length} 文字 → {longTokens.Count} 語、{watch.ElapsedMilliseconds} ms");
        Check("長い文も位置が合う", longTokens.Count > 100 && longTokens.All(t => string.CompareOrdinal(long_, t.Start, t.Surface, 0, t.Surface.Length) == 0));
        const string mixed = "Koebumi と 東海林さん 🙂 に送る";
        var mixedTokens = reader.Tokenize(mixed);
        Check("空白・英字・絵文字を含む文も位置が合う", mixedTokens.Count > 0 && mixedTokens.All(t => string.CompareOrdinal(mixed, t.Start, t.Surface, 0, t.Surface.Length) == 0));
        Check("空の文は空", reader.Tokenize("").Count == 0);
        var tokensFromCore = ScreenNameFixer.Tokens("渡邉さん", reader);
        Check("Core の ScreenNameFixer から使える", tokensFromCore.Count > 0 && tokensFromCore.Any(t => t.Reading.Length > 0));
        return Task.CompletedTask;
    }

    Task ForegroundAppTest()
    {
        // 最前面の窓がなくても確かめられるよう、シェル（エクスプローラー）の窓でも読む
        var shell = ForegroundApp.Describe(Native.GetShellWindow());
        if (shell == null) Skip("シェルの窓の情報", "窓がない");
        else
        {
            Write($"  シェルの窓: pid={shell.ProcessId} exe={shell.ExeName} 管理者={shell.IsElevatedAboveUs}");
            Check("シェルの窓の exe 名が取れる", shell.ExeName.Equals("explorer.exe", StringComparison.OrdinalIgnoreCase) && !shell.IsElevatedAboveUs);
        }
        var current = ForegroundApp.Current();
        if (current == null)
        {
            Skip("最前面の窓", "窓がない（切断・ロック中）");
            return Task.CompletedTask;
        }
        var info = CoreAppContext.Describe(current.ExeName, null, current.WindowTitle, current.ProcessId);
        Write($"  hwnd=0x{current.Hwnd:X} pid={current.ProcessId} exe={current.ExeName} 種類={info.Category} 管理者={current.IsElevatedAboveUs}");
        Write($"  タイトル: {current.WindowTitle}");
        Check("exe 名が取れる", current.ExeName.Length > 0);
        return Task.CompletedTask;
    }

    async Task SurroundingTextReaderTest()
    {
        var detail = await Task.Run(SurroundingTextReader.ReadDetailed);
        Write($"  方法: {detail.Info}、要素 {detail.Nodes} 個、{detail.Ms:F0} ms");
        if (detail.Text is { } t)
            Write($"  前 {t.Before.Length} 字、後 {t.After.Length} 字、窓の前 {t.Screen.Length} 字、窓の後 {t.ScreenAfter.Length} 字");
        var viaApi = await SurroundingTextReader.ReadAsync();
        Write($"  ReadAsync: {(viaApi == null ? "null" : "読めた")}");
        if (detail.Text == null) Skip("前面の窓の文脈", "読めなかった（" + detail.Info + "）");
        else Check("0.3 秒以内に読める", detail.Ms <= 300, $"{detail.Ms:F0} ms");
    }

    async Task AudioRecorderTest()
    {
        using var recorder = new AudioRecorder();
        int levels = 0;
        float maxLevel = 0;
        recorder.Level += l => { Interlocked.Increment(ref levels); maxLevel = Math.Max(maxLevel, l); };
        try
        {
            recorder.Start();
        }
        catch (AudioCaptureException e)
        {
            Skip("1 秒の録音", e.Message + (e.InnerException == null ? "" : " / " + e.InnerException.GetType().Name));
            return;
        }
        Write($"  録音中: {recorder.DeviceName}");
        await Task.Delay(1000);
        var audio = recorder.Stop();
        Write($"  {audio.Samples.Length} サンプル（{audio.Duration:F2} 秒、{audio.SampleRate:F0} Hz）、最大 {audio.Peak:F4}、RMS {audio.Rms:F4}、音量の通知 {levels} 回（最大 {maxLevel:F2}）");
        Check("約 1 秒分のサンプル", audio.Samples.Length is > 14000 and < 19000);
        Check("音量が約 20 Hz で届く", levels is >= 12 and <= 30, $"{levels} 回");
        Check("停止後は録音していない", !recorder.IsRecording);
    }

    async Task TextInserterTest()
    {
        await await app.Dispatcher.InvokeAsync(async () =>
        {
            using var inserter = new TextInserter();
            // 使う人のクリップボードは退避しておき、最後に戻す。試験には、テキストと独自の形式を持つ内容を使う
            var users = inserter.Snapshot();
            if (users == null)
            {
                Skip("クリップボード", "クリップボードを開けない");
                return;
            }
            Write($"  使う人のクリップボード: {users.Count} 形式（試験のあとで戻す）");
            var custom = Native.RegisterClipboardFormat("KoebumiSelfTestFormat");
            const string originalText = "koebumi-selftest-original 元のテキスト";
            List<TextInserter.Item> original =
            [
                new(Native.CF_UNICODETEXT, Encoding.Unicode.GetBytes(originalText + "\0")),
                new(custom, [1, 2, 3, 4, 5]),
            ];
            if (!inserter.Restore(original, excludeFromHistory: false))
            {
                Skip("クリップボード", "クリップボードを書けない");
                return;
            }
            // Windows が足す形式（CF_LOCALE など）も含めた、貼り付け前の姿
            var baseline = inserter.Snapshot()!;
            int sent = 0;
            inserter.SendPaste = () => { sent++; return true; };
            try
            {
                // 貼り付けると、文が入り、履歴に残さない形式が付く
                Check("貼り付けを送れる", await inserter.PasteAsync("koebumi-selftest-1") && sent == 1);
                Check("貼り付ける文が入る", inserter.GetText() == "koebumi-selftest-1");
                Check("履歴に残さない 3 つの形式が付く", TextInserter.HasExclusionFormats());
                // 戻す前の 2 回目の貼り付けは、最初の内容を使い回す
                await Task.Delay(250);
                await inserter.PasteAsync("koebumi-selftest-2");
                Check("2 回目の文が入る", inserter.GetText() == "koebumi-selftest-2");
                await Task.Delay(900);
                Check("600 ms 後に元のテキストへ戻る", inserter.GetText() == originalText);
                var after = inserter.Snapshot();
                Check("独自の形式も含め、元の形式がそろっている", after != null && SameItems(baseline, after), $"{after?.Count} 形式");
                Check("戻した内容にも履歴に残さない形式が付く", TextInserter.HasExclusionFormats());

                // 待っている間にほかのアプリがコピーしたら、戻さない
                await inserter.PasteAsync("koebumi-selftest-3");
                inserter.CopyToClipboard("koebumi-selftest-user-copy");
                await Task.Delay(900);
                Check("途中でコピーされたら戻さない", inserter.GetText() == "koebumi-selftest-user-copy");
                Check("コピーは履歴に残る形式", !TextInserter.HasExclusionFormats());

                // keepInClipboard なら戻さない
                await inserter.PasteAsync("koebumi-selftest-4", keepInClipboard: true);
                await Task.Delay(900);
                Check("keepInClipboard なら戻さない", inserter.GetText() == "koebumi-selftest-4");
                Write($"  変換中の文字（HasActiveComposition）: {inserter.HasActiveComposition()}");
            }
            finally
            {
                // どの場合も、使う人のクリップボードを元に戻す
                inserter.Restore(users, excludeFromHistory: false);
            }
            var finalItems = inserter.Snapshot();
            Check("試験のあと、使う人のクリップボードに戻した", finalItems != null && SameItems(users, finalItems), $"{finalItems?.Count} 形式");
        });
    }

    async Task HotkeyManagerTest()
    {
        var manager = await app.Dispatcher.InvokeAsync(() => new HotkeyManager(app.Dispatcher));
        try
        {
            var received = new List<string>();
            manager.CommandReceived += c => { lock (received) received.Add(c.ToString()); };
            manager.UpdateBindings(new AppSettings());
            const int LCtrl = 0xA2, LWin = 0x5B;

            // Ctrl を先に押す: Win は飲み込む
            var d1 = Feed(manager, (LCtrl, true), (LWin, true), (LWin, false), (LCtrl, false));
            Check("Ctrl→Win: Ctrl は通し Win は飲み込む", d1.SequenceEqual([HookDecision.Pass, HookDecision.Swallow, HookDecision.Swallow, HookDecision.Pass]), string.Join(",", d1));
            await WaitFor(() => Snapshot(received).Length >= 1);
            Check("Begin(Dictate) が UI スレッドに届く", Snapshot(received).SequenceEqual(["Begin(Dictate)"]), string.Join(",", Snapshot(received)));

            // もう一度押すと確定（ハンズフリー）。状態の写しはフックが先に Recording にしている
            var d2 = Feed(manager, (LCtrl, true), (LWin, true), (LWin, false), (LCtrl, false));
            await WaitFor(() => Snapshot(received).Length >= 2);
            Check("2 回目の押下で Finish", Snapshot(received).SequenceEqual(["Begin(Dictate)", "Finish"]), string.Join(",", Snapshot(received)) + " / " + string.Join(",", d2));

            // 処理中は新しい録音を始めない。UI スレッドが待機中に戻したあとは始める
            var d3 = Feed(manager, (LCtrl, true), (LWin, true), (LWin, false), (LCtrl, false));
            await Task.Delay(100);
            Check("処理中は Begin が出ない", Snapshot(received).Length == 2, string.Join(",", d3));
            await app.Dispatcher.InvokeAsync(() => manager.SetState(EngineState.Idle));

            // Win を先に押す: 通してしまった Win は、離すときに 0xE8 を挟んで送り直す
            manager.Reset();
            var d4 = Feed(manager, (LWin, true), (LCtrl, true), (LWin, false), (LCtrl, false));
            Check("Win→Ctrl: Win の離しで MaskAndReinject", d4.SequenceEqual([HookDecision.Pass, HookDecision.Pass, HookDecision.MaskAndReinject, HookDecision.Pass]), string.Join(",", d4));
            await WaitFor(() => Snapshot(received).Length >= 3);
            Check("Begin(Dictate) が届く", Snapshot(received).Length == 3 && Snapshot(received)[2] == "Begin(Dictate)", string.Join(",", Snapshot(received)));
            Check("フックは付けていない", !manager.IsRunning);
        }
        finally
        {
            manager.Dispose();
        }
    }

    async Task HookTest(bool desktop)
    {
        // 割り当てのないキー（0xE8）を使って、フックが自分の印つきのキーを素通しし、ほかのキーは渡すことを確かめる
        int unmarked = 0;
        bool injectedSeen = false;
        using var hook = new KeyboardHookThread(e =>
        {
            if (e.Vk == 0xE8)
            {
                Interlocked.Increment(ref unmarked);
                injectedSeen |= e.Injected;
            }
            return HookDecision.Pass;
        });
        Check("フックを付けられる", hook.Start());
        Check("動いている", hook.IsRunning);

        if (!desktop)
        {
            Skip("SendInput でキーを送る確認", "入力を受けるデスクトップがない");
        }
        else
        {
            var inputs = new[] { RawKey(0xE8, true), RawKey(0xE8, false) };
            uint count = Native.SendInput(2, inputs, Marshal.SizeOf<Native.INPUT>());
            await WaitFor(() => Volatile.Read(ref unmarked) >= 2);
            Check("印のないキーは handler に届く", count == 2 && unmarked == 2 && injectedSeen, $"送れた {count}、届いた {unmarked}");

            var before = unmarked;
            bool tapped = KeySender.Tap(0xE8);
            await Task.Delay(200);
            Check("KeySender の印つきのキーは handler に届かない", tapped && unmarked == before);
            Write($"  コールバックにかかった時間の最大: {hook.MaxCallbackMs:F3} ms");
            Check("コールバックは 5 ms 以内", hook.MaxCallbackMs < 5, $"{hook.MaxCallbackMs:F3} ms");
        }

        hook.Stop();
        Check("止めるとフックのスレッドが終わる", !hook.IsRunning);
        Check("付け直せる", hook.Start() && hook.IsRunning);
    }

    /// トレイのアイコンと前面の窓の監視を、作って壊せること（どちらも UI スレッドで）
    async Task ShellTest()
    {
        await app.Dispatcher.InvokeAsync(() =>
        {
            using (var tray = new TrayIcon())
            {
                Pass("トレイのアイコンを作れる");
            }
            using var watcher = new ForegroundWatcher();
            Check("前面の窓の監視を始められる", watcher.Start());
            watcher.Stop();
            Pass("止められる");
        });
    }

    // MARK: - 補助

    static Native.INPUT RawKey(ushort vk, bool down) => new()
    {
        type = Native.INPUT_KEYBOARD,
        u = new Native.InputUnion { ki = new Native.KEYBDINPUT { wVk = vk, dwFlags = down ? 0 : Native.KEYEVENTF_KEYUP } },
    };

    static List<HookDecision> Feed(HotkeyManager manager, params (int Vk, bool Down)[] keys) =>
        [.. keys.Select(k => manager.OnKey(new RawKeyEvent(k.Vk, k.Down, false)))];

    static string[] Snapshot(List<string> list)
    {
        lock (list) return [.. list];
    }

    static async Task WaitFor(Func<bool> condition, int timeoutMs = 1500)
    {
        var clock = Stopwatch.StartNew();
        while (!condition() && clock.ElapsedMilliseconds < timeoutMs) await Task.Delay(10);
    }

    static bool SameItems(List<TextInserter.Item> a, List<TextInserter.Item> b) =>
        a.Count == b.Count && a.OrderBy(i => i.Format).Zip(b.OrderBy(i => i.Format)).All(p => p.First.Format == p.Second.Format && p.First.Data.AsSpan().SequenceEqual(p.Second.Data));

    void Pass(string name, string detail = "") { passed++; Write($"  [成功] {name}{(detail.Length > 0 ? " — " + detail : "")}"); }
    void Fail(string name, string detail) { failed++; Write($"  [失敗] {name}{(detail.Length > 0 ? " — " + detail : "")}"); }
    void Skip(string name, string reason) { skipped++; Write($"  [飛ばした] {name} — {reason}"); }

    void Check(string name, bool ok, string detail = "")
    {
        if (ok) Pass(name, detail);
        else Fail(name, detail);
    }

    void Write(string line)
    {
        File.AppendAllText(logPath, line + "\n");
        try { console(line); } catch (Exception) { }
    }

    /// 親のコンソール（またはリダイレクト先）に書く関数。コンソールがなければ何もしない
    static Action<string> OpenConsole()
    {
        var handle = Native.GetStdHandle(Native.STD_OUTPUT_HANDLE);
        if (handle == IntPtr.Zero || handle == new IntPtr(-1))
        {
            if (!Native.AttachConsole(Native.ATTACH_PARENT_PROCESS)) return _ => { };
            handle = Native.CreateFile("CONOUT$", Native.GENERIC_WRITE, Native.FILE_SHARE_WRITE, IntPtr.Zero, Native.OPEN_EXISTING, 0, IntPtr.Zero);
            if (handle == new IntPtr(-1)) return _ => { };
        }
        // コンソールのコード ページ（日本語の Windows では CP932）に左右されないよう、画面には Unicode で書く
        if (Native.GetConsoleMode(handle, out _))
            return line => Native.WriteConsole(handle, line + "\r\n", (uint)(line.Length + 2), out _, IntPtr.Zero);
        var stream = new FileStream(new SafeFileHandle(handle, ownsHandle: false), FileAccess.Write);
        return line =>
        {
            stream.Write(Encoding.UTF8.GetBytes(line + "\n"));
            stream.Flush();
        };
    }
}
