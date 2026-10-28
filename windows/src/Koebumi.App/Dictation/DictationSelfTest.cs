using System.Diagnostics;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Koebumi.Core;

namespace Koebumi.App;

/// --selftest のうち、DictationController と VoiceBar の確認。人も、ネットワークも、入力先のアプリも使わない:
/// 音声認識と AI は偽物、入力は偽物、前面のアプリは偽物、声は KOEBUMI_FAKE_AUDIO の WAV。
/// 履歴・統計・設定は、一時フォルダ（Storage.RootOverride）に書いて、終わったら消す
sealed partial class SelfTest
{
    const string SnapshotVariable = "KOEBUMI_SELFTEST_SNAPSHOTS";
    const string SpokenText = "えーと、明日の会議は3時に、いや4時にしてください";

    sealed class FakeTranscriber : ITranscriber
    {
        public string Text = "";
        public Exception? Failure;
        public bool WaitForCancel;
        public bool Cancelled;
        public int Calls;
        public TranscriptionRequest? Last;

        public async Task<string> TranscribeAsync(RecordedAudio audio, TranscriptionRequest request, CancellationToken cancellationToken = default)
        {
            Calls++;
            Last = request;
            if (WaitForCancel)
            {
                try { await Task.Delay(Timeout.Infinite, cancellationToken); }
                catch (OperationCanceledException) { Cancelled = true; throw; }
            }
            if (Failure != null) throw Failure;
            return Text;
        }
    }

    sealed class FakeEngine(Func<PolishRequest, string> respond) : ILLMEngine
    {
        public string Name => "fake";
        public bool SupportsWebSearch => false;
        public int Calls;
        public PolishRequest? Last;

        public Task<string> PolishAsync(PolishRequest request, CancellationToken cancellationToken = default)
        {
            Calls++;
            Last = request;
            return Task.FromResult(respond(request));
        }

        public Task<AskOutcome> AskAsync(AskRequest request, CancellationToken cancellationToken = default) => throw new NotSupportedException();

        public Task<StyleAnalysis> AnalyzeStyleAsync(IReadOnlyList<StyleSample> samples, StyleProfile current, CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();
    }

    static ForegroundApp FakeApp(string exe, string title, bool elevated = false) => new(IntPtr.Zero, 4242, exe, title, elevated);

    static RecordedAudio Tone(double seconds, float amplitude)
    {
        var samples = new float[(int)(seconds * 16000)];
        for (int i = 0; i < samples.Length; i++) samples[i] = amplitude * MathF.Sin(2 * MathF.PI * 440 * i / 16000);
        return new RecordedAudio(samples);
    }

    async Task DictationControllerTest()
    {
        var root = Path.Combine(Path.GetTempPath(), "koebumi-selftest-" + Guid.NewGuid().ToString("N")[..8]);
        var previousRoot = Storage.RootOverride;
        var previousFake = Environment.GetEnvironmentVariable(AudioRecorder.FakeAudioVariable);
        var previousLanguage = L10n.Current;
        Directory.CreateDirectory(root);
        // 履歴・統計・設定は、使う人の %APPDATA%\Koebumi ではなく一時フォルダに書く
        Storage.RootOverride = Path.Combine(root, "data");
        try
        {
            var speech = Path.Combine(root, "speech.wav");
            var silence = Path.Combine(root, "silence.wav");
            File.WriteAllBytes(speech, WAV.Encode(Tone(1.2, 0.3f)));
            File.WriteAllBytes(silence, WAV.Encode(new RecordedAudio(new float[16000])));
            await await app.Dispatcher.InvokeAsync(() => DictationCases(speech, silence, root));
        }
        finally
        {
            Storage.RootOverride = previousRoot;
            Environment.SetEnvironmentVariable(AudioRecorder.FakeAudioVariable, previousFake);
            L10n.Current = previousLanguage;
            try { Directory.Delete(root, recursive: true); }
            catch (Exception e) { Write("  一時フォルダを消せない: " + e.Message); }
        }
    }

    async Task DictationCases(string speech, string silence, string root)
    {
        var services = new AppServices();
        services.Settings.Update(s =>
        {
            s.UiLanguage = UILanguage.Ja;
            s.LlmProvider = LLMProvider.None;
            s.ContextAwareness = ContextAwareness.Off;
        });
        Environment.SetEnvironmentVariable(AudioRecorder.FakeAudioVariable, speech);

        var inserted = new List<string>();
        var transcriber = new FakeTranscriber { Text = SpokenText };
        ILLMEngine? engine = null;
        ForegroundApp? target = FakeApp("notepad.exe", "無題 - メモ帳");
        SurroundingText? surrounding = null;
        int surroundingReads = 0;
        bool insertResult = true;
        var hooks = new DictationHooks
        {
            Transcriber = _ => transcriber,
            Engine = _ => engine,
            Insert = text => { inserted.Add(text); return Task.FromResult(insertResult); },
            Foreground = () => target,
            ReadSurrounding = () => { surroundingReads++; return Task.FromResult(surrounding); },
        };
        using var recorder = new AudioRecorder();
        using var manager = new HotkeyManager(app.Dispatcher);
        manager.UpdateBindings(services.Settings.Current);
        using var controller = new DictationController(services, app.Dispatcher, recorder, hotkeys: manager, hooks: hooks);

        var phases = new List<string>();
        controller.Changed += () =>
        {
            var kind = controller.Phase.Kind.ToString();
            if (phases.Count == 0 || phases[^1] != kind) phases.Add(kind);
        };

        // 話し始めから、入力し終えるまで
        async Task<string?> Speak(Mode mode = Mode.Dictate)
        {
            inserted.Clear();
            phases.Clear();
            controller.Handle(HotkeyCommand.Begin(mode));
            if (controller.Phase.Kind != PhaseKind.Recording) return null;
            await Task.Delay(250);
            controller.Handle(HotkeyCommand.Finish);
            await (controller.Processing ?? Task.CompletedTask);
            return inserted.LastOrDefault();
        }

        string Summary(HistoryItem item) =>
            $"{item.AppBundleID} {item.Category} {item.Mode} {item.Status} 語数={item.WordCount} 音声={(services.History.AudioPathOf(item) is { } p && File.Exists(p) ? "あり" : "なし")}"
            + $" 認識=「{item.RawTranscript}」 出力=「{item.Output}」" + (item.PlainOutput is null ? "" : $" 整形前=「{item.PlainOutput}」")
            + (item.ErrorMessage is null ? "" : $" エラー=「{item.ErrorMessage}」");

        // --- 整形しない: メモ帳とチャット
        var notepad = await Speak();
        Write($"  メモ帳（整形しない）→ 「{notepad}」   フェーズ: {string.Join(" → ", phases)}");
        Check("録音 → 処理中 → 待機の順に進む", phases.SequenceEqual(["Recording", "Processing", "Idle"]), string.Join(",", phases));
        Check("メモ帳に入力する文が出る", !string.IsNullOrEmpty(notepad) && !notepad.Contains("えーと"));
        Check("EngineState は待機に戻る", controller.EngineState.Kind == EngineStateKind.Idle && manager.StateProvider!().Kind == EngineStateKind.Idle);
        Check("認識の依頼: 話す言語と辞書", transcriber.Last is { Languages: ["ja-JP"] });
        var item = services.History.Items.FirstOrDefault();
        Check("履歴に 1 件（メモ帳・ドキュメント・音声つき）",
            services.History.Items.Count == 1 && item is { AppBundleID: "notepad.exe", AppName: "notepad", Category: AppCategory.Document, Mode: Mode.Dictate, Status: HistoryStatus.Success }
            && item.RawTranscript == SpokenText && item.Output == notepad && item.WordCount > 0 && services.History.AudioPathOf(item) is { } audioPath && File.Exists(audioPath),
            item is null ? "なし" : Summary(item));
        Check("統計に 1 回", services.Stats.Stats is { Sessions: 1, TotalWords: > 0 }, $"{services.Stats.Stats.Sessions} 回 {services.Stats.Stats.TotalWords} 語");
        Check("文体の学習の例に足される", services.Personalization.PendingCount == 1, $"{services.Personalization.PendingCount} 件");

        target = FakeApp("slack.exe", "general - Slack");
        var slack = await Speak();
        Write($"  Slack（整形しない）→ 「{slack}」");
        Check("Slack に入力する文が出る", !string.IsNullOrEmpty(slack));
        Check("Slack では句点を付けない（チャットの句読点）", slack is not null && !slack.Contains('。') && !slack.Contains('、'));
        Check("履歴の 1 件目が Slack・チャット", services.History.Items.FirstOrDefault() is { AppBundleID: "slack.exe", Category: AppCategory.Chat });

        // --- 偽の AI（そのまま返す）。依頼の中身を確かめる
        var echo = new FakeEngine(r => r.Transcript);
        engine = echo;
        services.Settings.Update(s => s.LlmProvider = LLMProvider.OpenAICompatible);
        services.Dictionary.Add("Koebumi", DictionarySource.Manual);
        var withEngine = await Speak();
        Write($"  Slack（偽の AI がそのまま返す）→ 「{withEngine}」");
        var request = echo.Last;
        Check("AI に依頼が届く", echo.Calls >= 1 && request is not null);
        Check("依頼: アプリ・種類・言語・口調",
            request is { AppName: "slack", Category: AppCategory.Chat, Mode: Mode.Dictate, ChatPunctuation: ChatPunctuation.NoPunctuation, AllowsRewording: false }
            && request.SourceLanguages.SequenceEqual(["ja-JP"]) && request.StyleDescription.Contains("chat", StringComparison.OrdinalIgnoreCase), request?.StyleDescription ?? "");
        Check("依頼: 辞書の語が入る", request?.Vocabulary.Contains("Koebumi") == true);
        Check("依頼: 表記のルール", request?.Notation is not null);
        Check("認識の依頼にも辞書の語が入る", transcriber.Last?.Vocabulary.Contains("Koebumi") == true);

        // --- 翻訳
        transcriber.Text = "明日の会議は4時にしてください";
        engine = new FakeEngine(_ => "Please hold tomorrow's meeting at 4 o'clock.");
        var translated = await Speak(Mode.Translate);
        Write($"  翻訳（偽の AI が英文を返す）→ 「{translated}」");
        var last = services.History.Items.FirstOrDefault();
        Check("翻訳の結果が入力される", translated == "Please hold tomorrow's meeting at 4 o'clock", translated ?? "");
        Check("履歴: 翻訳・翻訳先", last is { Mode: Mode.Translate, TargetLanguage: "en-US", Status: HistoryStatus.Success });
        Check("依頼: 翻訳先", ((FakeEngine)engine).Last is { Mode: Mode.Translate, TargetLanguage: "en-US" });

        engine = null;
        services.Settings.Update(s => s.LlmProvider = LLMProvider.None);
        var failedTranslation = await Speak(Mode.Translate);
        Check("AI なしの翻訳はエラーを出して入力しない", failedTranslation is null && controller.Phase is { Kind: PhaseKind.Message, IsError: true }, controller.Phase.Text);
        Write($"  翻訳（AI なし）→ エラー「{controller.Phase.Text}」");
        Check("失敗は履歴に残る", services.History.Items.FirstOrDefault() is { Status: HistoryStatus.Failed, Mode: Mode.Translate, ErrorMessage.Length: > 0 });

        // --- 認識のエラー（API キーがない）
        transcriber.Failure = TranscriptionException.MissingKey("OpenAI");
        var missingKey = await Speak();
        Write($"  API キーなし → 「{controller.Phase.Text}」");
        Check("API キーがないと、メッセージを出して入力しない",
            missingKey is null && controller.Phase is { Kind: PhaseKind.Message, IsError: true } && controller.Phase.Text.Contains("OpenAI") && controller.Phase.Text.Contains("API キー"));
        transcriber.Failure = null;
        transcriber.Text = SpokenText;

        // --- 声がない
        Environment.SetEnvironmentVariable(AudioRecorder.FakeAudioVariable, silence);
        var before = services.History.Items.Count;
        var silent = await Speak();
        Check("無音なら認識せずに知らせる", silent is null && controller.Phase is { Kind: PhaseKind.Message, IsError: false }
            && services.History.Items.Count == before, controller.Phase.Text);
        Environment.SetEnvironmentVariable(AudioRecorder.FakeAudioVariable, speech);

        // --- 管理者として動くアプリ・Ask anything
        target = FakeApp("taskmgr.exe", "タスク マネージャー", elevated: true);
        phases.Clear();
        controller.Handle(HotkeyCommand.Begin(Mode.Dictate));
        Check("管理者として動くアプリには録音しない", !recorder.IsRecording && controller.Phase is { Kind: PhaseKind.Message, IsError: true }
            && controller.Phase.Text == "管理者として動いているアプリには入力できません", controller.Phase.Text);
        target = FakeApp("notepad.exe", "無題 - メモ帳");
        controller.Handle(HotkeyCommand.Begin(Mode.Ask));
        Check("Ask anything は録音せずに知らせる", !recorder.IsRecording && controller.Phase is { Kind: PhaseKind.Message, IsError: false }, controller.Phase.Text);
        controller.Handle(HotkeyCommand.RevertLast);
        Check("AI の整形を戻す機能はまだ使えないと知らせる", controller.Phase is { Kind: PhaseKind.Message, IsError: false }, controller.Phase.Text);

        // --- 管理者として動くアプリが前面になった
        controller.Handle(HotkeyCommand.Begin(Mode.Dictate));
        controller.NotifyElevatedForeground();
        Check("録音中に管理者として動くアプリが前面になったら、録音を捨てて知らせる",
            !recorder.IsRecording && controller.Phase is { Kind: PhaseKind.Message, IsError: true } && controller.EngineState.Kind == EngineStateKind.Idle, controller.Phase.Text);

        // --- 途中でやめる
        controller.Handle(HotkeyCommand.Begin(Mode.Dictate));
        Check("録音中の EngineState", controller.EngineState == EngineState.Recording(Mode.Dictate) && manager.StateProvider!() == EngineState.Recording(Mode.Dictate));
        controller.Handle(HotkeyCommand.SwitchMode(Mode.Translate));
        Check("録音中に翻訳へ切り替えられる", controller.Mode == Mode.Translate && controller.EngineState == EngineState.Recording(Mode.Translate)
            && manager.StateProvider!() == EngineState.Recording(Mode.Translate));
        controller.Handle(HotkeyCommand.Abort);
        Check("Abort で待機に戻り、録音は止まる", controller.Phase.Kind == PhaseKind.Idle && !recorder.IsRecording);
        controller.Handle(HotkeyCommand.Begin(Mode.Dictate));
        controller.Handle(HotkeyCommand.SwitchMode(Mode.Ask));
        Check("録音中に Ask anything へ切り替えると、録音を捨てて知らせる", !recorder.IsRecording && controller.Phase is { Kind: PhaseKind.Message, IsError: false }, controller.Phase.Text);
        controller.Handle(HotkeyCommand.Begin(Mode.Dictate));
        controller.Handle(HotkeyCommand.Cancel);
        Check("録音中の Esc で待機に戻る", controller.Phase.Kind == PhaseKind.Idle && !recorder.IsRecording);

        transcriber.WaitForCancel = true;
        var historyBefore = services.History.Items.Count;
        inserted.Clear();
        controller.Handle(HotkeyCommand.Begin(Mode.Dictate));
        await Task.Delay(100);
        controller.Handle(HotkeyCommand.Finish);
        await Task.Delay(400);
        Check("処理中の EngineState は Busy", controller.Phase.Kind == PhaseKind.Processing && controller.EngineState.Kind == EngineStateKind.Busy && manager.StateProvider!().Kind == EngineStateKind.Busy);
        controller.Handle(HotkeyCommand.Cancel);
        await (controller.Processing ?? Task.CompletedTask);
        await Task.Delay(50);
        Check("処理中の Esc で、取り消して何も入力しない", controller.Phase.Kind == PhaseKind.Idle && inserted.Count == 0 && transcriber.Cancelled
            && services.History.Items.Count == historyBefore);
        transcriber.WaitForCancel = false;

        // --- 定型文・最後の結果の貼り付け・入力できなかったとき
        services.Settings.Update(s => s.Snippets = [new Snippet { Trigger = "署名", Text = "山田太郎\nKoebumi 株式会社" }]);
        transcriber.Text = "署名";
        engine = null;
        var snippet = await Speak();
        Write($"  定型文「署名」→ 「{snippet}」");
        Check("呼び出す言葉だけを話すと定型文が入る", snippet == "山田太郎\nKoebumi 株式会社", snippet ?? "");
        inserted.Clear();
        controller.Handle(HotkeyCommand.PasteLast);
        await Task.Delay(100);
        Check("最後の結果をもう一度入力する", inserted.SequenceEqual([snippet!]));
        transcriber.Text = SpokenText;
        insertResult = false;
        await Speak();
        Check("入力できなかったときは、コピーしたと知らせる", controller.Phase is { Kind: PhaseKind.Message, IsError: false } && controller.Phase.Text.Contains("クリップボード"), controller.Phase.Text);
        insertResult = true;

        // --- 画面の文脈: 設定で読むかどうか、音声認識のヒントに渡してよいか
        surrounding = new SurroundingText { Before = "お疲れ様です。", Screen = "渡邉さんと Slack で会議の件を話す" };
        await Speak();
        Check("画面の文脈を読まない設定では読まない", surroundingReads == 0);
        services.Settings.Update(s => s.ContextAwareness = ContextAwareness.LocalOnly);
        await Speak();
        Check("この PC の中だけ: 読むが、クラウドの音声認識にはヒントを渡さない", surroundingReads == 1 && transcriber.Last?.Vocabulary.Contains("渡邉") == false,
            string.Join(",", transcriber.Last?.Vocabulary ?? []));
        services.Settings.Update(s => s.ContextAwareness = ContextAwareness.Always);
        await Speak();
        Check("常に使う: 画面の語を音声認識のヒントに渡す", surroundingReads == 2 && transcriber.Last?.Vocabulary.Contains("渡邉") == true,
            string.Join(",", transcriber.Last?.Vocabulary ?? []));
        services.Settings.Update(s => s.ContextAwareness = ContextAwareness.Off);

        // --- ショートカットのキーから（HotkeyManager → DictationController）
        inserted.Clear();
        const int LCtrl = 0xA2, LWin = 0x5B;
        Feed(manager, (LCtrl, true), (LWin, true), (LWin, false), (LCtrl, false));
        await WaitFor(() => controller.Phase.Kind == PhaseKind.Recording, 3000);
        Check("Ctrl+Win で録音が始まる", controller.Phase.Kind == PhaseKind.Recording && controller.Mode == Mode.Dictate);
        Feed(manager, (LCtrl, true), (LWin, true), (LWin, false), (LCtrl, false));
        await WaitFor(() => controller.Processing is { IsCompleted: false } || inserted.Count > 0);
        await (controller.Processing ?? Task.CompletedTask);
        Check("もう一度押すと確定して入力する", inserted.Count == 1 && controller.Phase.Kind == PhaseKind.Idle, string.Join(",", inserted));

        // --- あとに残ったもの
        Write($"  履歴 {services.History.Items.Count} 件、統計 {services.Stats.Stats.Sessions} 回・{services.Stats.Stats.TotalWords} 語、文体の学習の例 {services.Personalization.PendingCount} 件");
        foreach (var h in services.History.Items.Reverse()) Write("    " + Summary(h));

        await VoiceBarChecks(services, controller);
    }

    async Task VoiceBarChecks(AppServices services, DictationController controller)
    {
        Write("\n== VoiceBar");
        using var bar = new VoiceBar(controller, services.Settings);
        const long Required = VoiceBarNative.WS_EX_NOACTIVATE | VoiceBarNative.WS_EX_TOOLWINDOW | VoiceBarNative.WS_EX_TOPMOST;
        Check("窓の拡張スタイル: NOACTIVATE・TOOLWINDOW・TOPMOST", (bar.ExtendedStyle & Required) == Required, $"0x{bar.ExtendedStyle:X}");
        Check("見えていない", !bar.IsVisible && !bar.IsShown);
        Check("app.manifest: PerMonitorV2 の DPI 対応", VoiceBarNative.AreDpiAwarenessContextsEqual(VoiceBarNative.GetThreadDpiAwarenessContext(), VoiceBarNative.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2));

        var foreground = Native.GetForegroundWindow();
        controller.SetPreviewState(DictationPhase.Message("音声バーの確認", isError: false), Mode.Dictate);
        await Task.Delay(400);
        Check("知らせを出すと窓が見える", bar.IsVisible && bar.IsShown);
        Check("前面の窓は変わらない（フォーカスを奪わない）", Native.GetForegroundWindow() == foreground);
        if (bar.Placement() is { } placed)
        {
            var (window, work, scale) = placed;
            Write($"  窓 ({window.Left},{window.Top})-({window.Right},{window.Bottom}) {window.Width}×{window.Height}px、作業領域 ({work.Left},{work.Top})-({work.Right},{work.Bottom})、倍率 {scale:F2}");
            Check("作業領域の中に収まる", window.Left >= work.Left && window.Right <= work.Right && window.Top >= work.Top && window.Bottom <= work.Bottom);
            Check("左右の真ん中", Math.Abs((window.Left + window.Right) - (work.Left + work.Right)) <= 2);
            var expectedGap = (int)Math.Round(16 * scale);
            Check("下端から余白 + 影の余白だけ上", Math.Abs(work.Bottom - window.Bottom - expectedGap) <= 2, $"{work.Bottom - window.Bottom}px（期待 {expectedGap}px）");
        }
        else
        {
            Skip("窓の位置", "モニターの情報を取れない");
        }

        // 状態ごとの大きさ（DIP）。見た目の確認は画像でするが、接続中のデスクトップがないと描けないので、大きさだけでも確かめる
        (string Name, DictationPhase Phase, Mode Mode, double MinHeight, double MaxHeight)[] sizes =
        [
            ("録音中", DictationPhase.Recording, Mode.Dictate, 65, 67),
            ("録音中（翻訳）", DictationPhase.Recording, Mode.Translate, 65, 67),
            ("処理中", DictationPhase.Processing, Mode.Dictate, 65, 67),
            ("知らせ（1 行）", DictationPhase.Message("入力できなかったので、クリップボードにコピーしました", false), Mode.Dictate, 65, 67),
            ("エラー（長い）", DictationPhase.Message(string.Concat(Enumerable.Repeat("とても長い説明 ", 30)), true), Mode.Dictate, 78, 96),
        ];
        foreach (var (name, phase, mode, minHeight, maxHeight) in sizes)
        {
            controller.SetPreviewState(phase, mode);
            await Task.Delay(250);
            if (bar.Placement() is not { } p) continue;
            double width = p.Window.Width / p.Scale, height = p.Window.Height / p.Scale;
            Write($"  {name}: {width:F0} × {height:F0} DIP（影の余白を含む）");
            Check($"高さ: {name}", height >= minHeight && height <= maxHeight, $"{height:F1} DIP");
            Check($"真ん中に置き直される: {name}", Math.Abs((p.Window.Left + p.Window.Right) - (p.Work.Left + p.Work.Right)) <= 2
                && Math.Abs(p.Work.Bottom - p.Window.Bottom - (int)Math.Round(16 * p.Scale)) <= 2);
        }

        if (Environment.GetEnvironmentVariable(SnapshotVariable) is { Length: > 0 } directory)
        {
            if (WriteSnapshots(services, controller, bar, directory)) Write($"  画像を {directory} に書いた");
            else Skip("音声バーの画像", "WPF が描けない（接続中のデスクトップがない）");
        }

        // 知らせは 2 秒で消える（消えるときは 0.2 秒かけてフェードする）
        controller.SetPreviewState(DictationPhase.Idle, Mode.Dictate);
        await WaitFor(() => !bar.IsVisible, 1500);
        Check("待機に戻ると窓が隠れる", !bar.IsVisible && !bar.IsShown);
        controller.ShowMessage("自動で消える知らせ", isError: false);
        await Task.Delay(300);
        Check("もう一度出る", bar.IsVisible);
        await WaitFor(() => !bar.IsVisible, 3500);
        Check("知らせは 2 秒ほどで消える", !bar.IsVisible && controller.Phase.Kind == PhaseKind.Idle);
        Check("最後まで前面の窓は変わらない", Native.GetForegroundWindow() == foreground);
    }

    /// 状態ごとの見た目を PNG に書く（ライトとダーク）。接続中のデスクトップがないと WPF は何も描かず、空の画像になるので、その場合は false
    static bool WriteSnapshots(AppServices services, DictationController controller, VoiceBar bar, string directory)
    {
        Directory.CreateDirectory(directory);
        try
        {
            foreach (var appearance in new[] { Appearance.Light, Appearance.Dark })
            {
                services.Settings.Update(s => s.Appearance = appearance);
                var backdrop = appearance == Appearance.Light ? Color.FromRgb(0xc9, 0xcd, 0xd4) : Color.FromRgb(0x3b, 0x40, 0x48);
                (string Name, DictationPhase Phase, Mode Mode)[] views =
                [
                    ("recording", DictationPhase.Recording, Mode.Dictate),
                    ("recording-translate", DictationPhase.Recording, Mode.Translate),
                    ("processing", DictationPhase.Processing, Mode.Dictate),
                    ("info", DictationPhase.Message("入力できなかったので、クリップボードにコピーしました", false), Mode.Dictate),
                    ("error", DictationPhase.Message("管理者として動いているアプリには入力できません", true), Mode.Dictate),
                    ("error-long", DictationPhase.Message("AI 整形に失敗したため認識結果を入力しました: API キーが無効です (401) " + string.Concat(Enumerable.Repeat("とても長い説明 ", 12)), true), Mode.Dictate),
                ];
                foreach (var (name, phase, mode) in views)
                {
                    controller.SetPreviewState(phase, mode);
                    var image = bar.Snapshot(backdrop);
                    var pixels = new byte[image.PixelWidth * image.PixelHeight * 4];
                    image.CopyPixels(pixels, image.PixelWidth * 4, 0);
                    if (!pixels.Any(b => b != 0)) return false;
                    var encoder = new PngBitmapEncoder();
                    encoder.Frames.Add(BitmapFrame.Create(image));
                    var file = Path.Combine(directory, $"voicebar-{appearance.ToString().ToLowerInvariant()}-{name}.png");
                    using var stream = File.Create(file);
                    encoder.Save(stream);
                }
            }
            return true;
        }
        finally
        {
            services.Settings.Update(s => s.Appearance = Appearance.System);
        }
    }
}
