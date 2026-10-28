using System.Diagnostics;
using System.Net.Http;
using System.Windows.Threading;
using Koebumi.Core;
using CoreAppContext = Koebumi.Core.AppContext;

namespace Koebumi.App;

public enum PhaseKind { Idle, Recording, Processing, Message }

/// 音声バーに出す状態。Message は一時的な知らせ（Text と、エラーかどうか）
public readonly record struct DictationPhase(PhaseKind Kind, string Text = "", bool IsError = false)
{
    public static DictationPhase Idle => default;
    public static DictationPhase Recording => new(PhaseKind.Recording);
    public static DictationPhase Processing => new(PhaseKind.Processing);
    public static DictationPhase Message(string text, bool isError) => new(PhaseKind.Message, text, isError);
}

/// 試験で本物の代わりに差し込むもの。null のところは本物を使う
public sealed class DictationHooks
{
    public Func<AppSettings, ITranscriber>? Transcriber { get; init; }
    public Func<AppSettings, ILLMEngine?>? Engine { get; init; }
    /// 入力の最後の段（貼り付け）。入力できたら true
    public Func<string, Task<bool>>? Insert { get; init; }
    public Func<ForegroundApp?>? Foreground { get; init; }
    public Func<Task<SurroundingText?>>? ReadSurrounding { get; init; }
}

/// 録音 → 音声認識 → 整形 → 入力の流れ。Mac 版の DictationController に当たる（フェーズ 1 の範囲: ディクテーションと翻訳）。
/// UI スレッドで作って、UI スレッドから使う。状態が変わると Changed を UI スレッドで出し、HotkeyManager の状態の写しも直す。
/// Ask anything・AI の整形を戻す・エージェントの操作・録音中の書き起こしの表示・入力中のミュートは、まだ移していない
public sealed class DictationController : IDisposable
{
    /// 録音の長さの上限。超えたら自動で確定する
    public static readonly TimeSpan MaxDuration = TimeSpan.FromMinutes(10);
    /// キーを離した直後の語尾まで録れるよう、確定してから録音を止めるまで待つ時間
    const int TailMs = 150;

    readonly AppServices services;
    readonly Dispatcher dispatcher;
    readonly AudioRecorder recorder;
    readonly HotkeyManager? hotkeys;
    readonly Func<AppSettings, ITranscriber> makeTranscriber;
    readonly Func<AppSettings, ILLMEngine?> makeEngine;
    readonly Func<string, Task<bool>> insert;
    readonly Func<ForegroundApp?> foreground;
    readonly Func<Task<SurroundingText?>> readSurrounding;
    readonly DispatcherTimer tick;
    readonly Stopwatch recordClock = new();

    DictationPhase phase;
    Mode mode = Mode.Dictate;
    float level;
    TimeSpan elapsed;
    /// 録音ごとに増える番号。取り消した古い処理が、新しい録音の状態を書き換えないようにする
    int generation;
    AppContextInfo context = AppContextInfo.Unknown;
    string sessionLanguage = "ja-JP";
    Task<SurroundingText?>? surroundingTask;
    CancellationTokenSource? processingCts;
    CancellationTokenSource? messageCts;
    Task? processingTask;
    bool disposed;

    /// 1 回の録音の処理に必要なもの
    sealed record Job(int Generation, Mode Mode, AppContextInfo Context, string Language, string? TargetLanguage, Task<SurroundingText?>? Surrounding);

    /// 録音の状態・モード・音量・経過時間のどれかが変わった（UI スレッドで呼ばれる）
    public event Action? Changed;

    public DictationPhase Phase => phase;
    public Mode Mode => mode;
    /// 今の声の大きさ（0〜1）。約 20 回/秒で届く。なめらかにするのは音声バー側（Mac 版と同じ）
    public float Level => level;
    public TimeSpan Elapsed => elapsed;

    /// HotkeyManager に渡す状態（Mac 版の engineState と同じ対応）
    public EngineState EngineState => phase.Kind switch
    {
        PhaseKind.Recording => EngineState.Recording(mode),
        PhaseKind.Processing => EngineState.Busy,
        _ => EngineState.Idle,
    };

    /// 認識・整形・入力・履歴の保存まで終わると完了する Task（試験用）
    internal Task? Processing => processingTask;

    AppSettings settings => services.Settings.Current;

    /// hotkeys があれば、コマンドを受け取り、StateProvider になる。inserter は、hooks.Insert を渡さないときに必要
    public DictationController(AppServices services, Dispatcher dispatcher, AudioRecorder recorder, TextInserter? inserter = null,
        HotkeyManager? hotkeys = null, DictationHooks? hooks = null)
    {
        this.services = services;
        this.dispatcher = dispatcher;
        this.recorder = recorder;
        this.hotkeys = hotkeys;
        makeTranscriber = hooks?.Transcriber ?? (s => TranscriberFactory.Make(s, services.Secrets));
        makeEngine = hooks?.Engine ?? (s => LLMFactory.Make(s, services.Secrets));
        foreground = hooks?.Foreground ?? ForegroundApp.Current;
        readSurrounding = hooks?.ReadSurrounding ?? SurroundingTextReader.ReadAsync;
        if (hooks?.Insert is { } custom) insert = custom;
        else if (inserter is not null) insert = async text =>
        {
            // 話している間に、管理者として動くアプリが前面になっていたら、貼り付けても捨てられる（エラーも出ない）。結果を失わないよう、コピーだけする
            if (this.foreground() is { IsElevatedAboveUs: true })
            {
                inserter.CopyToClipboard(text);
                return false;
            }
            return await inserter.InsertAsync(text, settings.KeepResultInClipboard);
        };
        else throw new ArgumentException("inserter か hooks.Insert が要ります");

        tick = new DispatcherTimer(DispatcherPriority.Normal, dispatcher) { Interval = TimeSpan.FromMilliseconds(100) };
        tick.Tick += OnTick;
        recorder.Level += OnRecorderLevel;
        recorder.Error += OnRecorderError;
        if (hotkeys is not null)
        {
            hotkeys.StateProvider = () => EngineState;
            hotkeys.CommandReceived += Handle;
        }
    }

    public void Handle(HotkeyCommand command)
    {
        try
        {
            switch (command.Kind)
            {
                case HotkeyCommandKind.Begin: Begin(command.Mode); break;
                case HotkeyCommandKind.SwitchMode: SwitchMode(command.Mode); break;
                case HotkeyCommandKind.Finish: Finish(); break;
                case HotkeyCommandKind.Cancel: Cancel(); break;
                case HotkeyCommandKind.Abort: Abort(); break;
                case HotkeyCommandKind.PasteLast: PasteLast(); break;
                case HotkeyCommandKind.RevertLast: RevertLast(); break;
            }
        }
        catch (Exception e)
        {
            // 想定外の失敗でも、状態が録音中・処理中のまま残らないようにする
            Debug.WriteLine($"[Koebumi] {command} の処理に失敗: {e}");
            if (phase.Kind == PhaseKind.Recording) AbortRecording();
            if (phase.Kind != PhaseKind.Processing) ShowMessage(ErrorText(e), true);
        }
    }

    // MARK: - 録音

    public void Begin(Mode newMode)
    {
        if (phase.Kind is PhaseKind.Recording or PhaseKind.Processing) return;
        CancelMessageTimer();
        if (newMode == Mode.Ask)
        {
            ShowMessage(AskUnavailable, false);
            return;
        }

        var app = foreground();
        // 管理者として動くアプリには、キーも貼り付けも届かない（UIPI）。録音する前に知らせる
        if (app is { IsElevatedAboveUs: true })
        {
            ShowMessage(ElevatedMessage, true);
            return;
        }

        var s = settings;
        // 文体の学習が AI を使っていると、この録音の整形がその後ろで待たされる
        services.Personalization.CancelAnalysis();
        generation++;
        mode = newMode;
        context = app is null
            ? AppContextInfo.Unknown
            : CoreAppContext.Describe(app.ExeName, null, app.WindowTitle, app.ProcessId, s.AppCategoryOverrides);
        sessionLanguage = s.CurrentDictationLanguage;
        surroundingTask = StartReadingSurrounding(s, app);

        try
        {
            recorder.Start(s.MicrophoneId);
        }
        catch (AudioCaptureException e)
        {
            surroundingTask = null;
            ShowMessage(e.Message, true);
            return;
        }

        level = 0;
        elapsed = TimeSpan.Zero;
        recordClock.Restart();
        tick.Start();
        SetPhase(DictationPhase.Recording);
    }

    /// 入力欄とウィンドウの文字列を、録音と並行して読む（応答の遅いアプリでも UI を止めない）
    Task<SurroundingText?>? StartReadingSurrounding(AppSettings s, ForegroundApp? app)
    {
        if (s.ContextAwareness == ContextAwareness.Off || app?.ProcessId == Environment.ProcessId) return null;
        // 窓の文字列は、AI か音声認識に渡してよいときだけ使う（Mac 版と同じ。読み取りそのものは入力欄と一緒に済む）
        var includeScreen = s.ShareSurroundingWithLLM || s.ShareSurroundingWithSTT;
        return ReadSurroundingAsync(includeScreen);
    }

    async Task<SurroundingText?> ReadSurroundingAsync(bool includeScreen)
    {
        try
        {
            var read = await readSurrounding();
            if (read is null) return null;
            return includeScreen ? read : read with { Screen = "", ScreenAfter = "" };
        }
        catch (Exception e)
        {
            Debug.WriteLine($"[Koebumi] 画面の文脈を読めない: {e.Message}");
            return null;
        }
    }

    public void SwitchMode(Mode newMode)
    {
        if (phase.Kind != PhaseKind.Recording || newMode == mode) return;
        if (newMode == Mode.Ask)
        {
            // Ask anything はフェーズ 2。録音を捨てて知らせる
            AbortRecording();
            ShowMessage(AskUnavailable, false);
            return;
        }
        mode = newMode;
        Publish();
    }

    /// 録音を確定して、認識・整形・入力に進む
    public void Finish()
    {
        if (phase.Kind != PhaseKind.Recording) return;
        var job = new Job(generation, mode, context, sessionLanguage,
            mode == Mode.Translate ? settings.CurrentTranslationTarget : null, surroundingTask);
        surroundingTask = null;
        processingCts?.Dispose();
        var cts = processingCts = new CancellationTokenSource();
        SetPhase(DictationPhase.Processing);
        processingTask = ProcessAsync(job, cts.Token);
    }

    /// Esc。録音中なら捨て、処理中なら取り消して何も入力しない
    public void Cancel()
    {
        switch (phase.Kind)
        {
            case PhaseKind.Recording:
                AbortRecording();
                break;
            case PhaseKind.Processing:
                processingCts?.Cancel();
                generation++;
                if (recorder.IsRecording) StopRecording();
                SetPhase(DictationPhase.Idle);
                break;
        }
    }

    /// 管理者として動くアプリが前面になった（そのあいだ、ショートカットのキーも貼り付けも届かない。docs/windows.md の「気をつけること」）。
    /// 録音中なら捨てて、処理中でなければ知らせる
    public void NotifyElevatedForeground()
    {
        if (phase.Kind == PhaseKind.Processing) return;
        if (phase.Kind == PhaseKind.Recording) AbortRecording();
        ShowMessage(ElevatedMessage, true);
    }

    /// Ctrl+Win + 矢印キーなど、ディクテーションのつもりではなかった操作。黙って止める
    public void Abort()
    {
        if (phase.Kind == PhaseKind.Recording) AbortRecording();
    }

    void AbortRecording()
    {
        StopRecording();
        surroundingTask = null;
        generation++;
        SetPhase(DictationPhase.Idle);
    }

    RecordedAudio StopRecording()
    {
        tick.Stop();
        return recorder.Stop();
    }

    void OnTick(object? sender, EventArgs e)
    {
        if (phase.Kind != PhaseKind.Recording) return;
        elapsed = recordClock.Elapsed;
        Changed?.Invoke();
        if (elapsed >= MaxDuration) Finish();
    }

    // 録音のスレッドから呼ばれる
    void OnRecorderLevel(float value) => dispatcher.BeginInvoke(() =>
    {
        if (phase.Kind != PhaseKind.Recording) return;
        level = value;
        Changed?.Invoke();
    });

    void OnRecorderError(Exception error) => dispatcher.BeginInvoke(() =>
    {
        if (phase.Kind != PhaseKind.Recording) return;
        AbortRecording();
        ShowMessage(T("録音が止まりました: ", "Recording stopped: ") + error.Message, true);
    });

    // MARK: - 認識と整形

    async Task ProcessAsync(Job job, CancellationToken ct)
    {
        try
        {
            await Task.Delay(TailMs, ct);
            // 待っている間に取り消されたなら、録音は取り消した側が止めている
            if (job.Generation != generation) return;
            var audio = StopRecording();
            await RunAsync(audio, job, ct);
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception e)
        {
            Debug.WriteLine($"[Koebumi] 処理に失敗: {e}");
            if (job.Generation == generation && !ct.IsCancellationRequested) ShowMessage(ErrorText(e), true);
        }
    }

    async Task RunAsync(RecordedAudio audio, Job job, CancellationToken ct)
    {
        if (audio.IsSilent)
        {
            ShowMessage(T("音声が検出されませんでした", "No speech detected"), false);
            return;
        }

        bool IsCurrent() => job.Generation == generation && !ct.IsCancellationRequested;
        var s = settings;
        var ctx = job.Context;
        var surrounding = job.Surrounding is null ? null : await job.Surrounding;
        var id = Guid.NewGuid();
        var raw = "";

        try
        {
            // 画面の語を音声認識のヒントにする（音声認識を画面の文脈に使ってよいときだけ）
            raw = await TranscribeAsync(audio, s, s.ShareSurroundingWithSTT && surrounding is not null ? surrounding.Terms : [], ct);
            ct.ThrowIfCancellationRequested();
            if (raw.Length == 0) throw TranscriptionException.Empty();

            // 「署名」のように呼び出す言葉だけを話した文は、登録した定型文にする（AI に通さない）。
            // メールなら、画面の受信メールから返信先の名前と間柄を読む（この PC の中だけで使う）。どちらも名前の読みを使うので、UI スレッドの外で
            var (parts, reply) = await Task.Run(() => (
                job.Mode == Mode.Dictate ? SnippetExpander.Split(raw, s.Snippets) : new SnippetExpander.Parts { Body = raw },
                ctx.Category == AppCategory.Email && s.MailReplyStyle && surrounding is not null ? MailReply.Context(surrounding) : null), ct);

            string output = "", plain = "";
            string? warning = null;
            if (parts.Body.Length > 0 || parts.HasSnippets)
            {
                var body = new Polisher.Output("");
                if (parts.Body.Length > 0)
                {
                    body = await PolishAsync(parts.Body, job, s, ctx, SnippetExpander.Surrounding(surrounding, parts, reply), reply, ct);
                }
                warning = body.Warning;
                var lead = ctx.Category == AppCategory.Email ? SnippetExpander.LeadingBreak(parts, surrounding?.Before) : "";
                output = lead + SnippetExpander.Join(parts, body.Text, reply);
                plain = lead + SnippetExpander.Join(parts, body.Plain.Length == 0 ? body.Text : body.Plain, reply);
            }
            ct.ThrowIfCancellationRequested();
            // 「えーと」だけなど、整形すると何も残らなかった
            if (output.Length == 0) throw TranscriptionException.Empty();

            var inserted = await insert(output);
            var item = new HistoryItem
            {
                Id = id,
                Mode = job.Mode,
                RawTranscript = raw,
                Output = output,
                PlainOutput = plain.Length > 0 && plain != output ? plain : null,
                AppName = ctx.AppName,
                AppBundleID = ctx.ExeName,
                Category = ctx.Category,
                Duration = audio.Duration,
                WordCount = StatsStore.WordCount(output),
                Language = job.Language,
                TargetLanguage = job.TargetLanguage,
            };
            if (IsCurrent())
            {
                if (warning is not null) ShowMessage(warning, true);
                else if (!inserted) ShowMessage(CopiedMessage, false);
                else SetPhase(DictationPhase.Idle);
            }
            await CommitAsync(item, audio, s, spoken: job.Mode == Mode.Dictate ? raw : null);
        }
        catch (Exception e)
        {
            // 取り消された（HttpClient の取り消しも含む）なら、履歴に残さず黙って終える
            if (e is OperationCanceledException || !IsCurrent()) return;
            var message = ErrorText(e);
            ShowMessage(message, true);
            await CommitAsync(new HistoryItem
            {
                Id = id,
                Mode = job.Mode,
                Status = HistoryStatus.Failed,
                RawTranscript = raw,
                ErrorMessage = message,
                AppName = ctx.AppName,
                AppBundleID = ctx.ExeName,
                Category = ctx.Category,
                Duration = audio.Duration,
                Language = job.Language,
                TargetLanguage = job.TargetLanguage,
            }, audio, s, spoken: null);
        }
    }

    /// 音声・統計・文体の学習・履歴を保存する。ファイルへの書き込みなので UI スレッドの外で行う
    Task CommitAsync(HistoryItem item, RecordedAudio audio, AppSettings s, string? spoken) => Task.Run(() =>
    {
        try
        {
            if (item.Status == HistoryStatus.Success)
            {
                services.Stats.Record(item.WordCount, audio.Duration);
                // 話した文を、文体の学習の例に足す
                if (spoken is not null && s.PersonalizationEnabled)
                {
                    services.Personalization.AddSample(new StyleSample(item.Category, spoken), makeEngine(s));
                }
            }
            // 音声は履歴を残すときだけ保存する（保存しない設定の履歴は音声ごと消える）
            if (s.KeepAudio && s.HistoryRetention != Retention.Never)
            {
                item = item with { AudioFile = services.History.SaveAudio(audio, item.Id) };
            }
            services.History.Add(item, s.HistoryRetention);
        }
        catch (Exception e)
        {
            Debug.WriteLine($"[Koebumi] 履歴の保存に失敗: {e}");
        }
    });

    Task<string> TranscribeAsync(RecordedAudio audio, AppSettings s, IReadOnlyList<string> screenTerms, CancellationToken ct)
    {
        var dictionary = services.Dictionary.Terms;
        // 画面から拾った語を辞書の前に足す（ヒントの数に上限があるため、その場の語を優先する）
        var request = new TranscriptionRequest
        {
            Languages = s.DictationLanguages,
            Vocabulary = [.. screenTerms.Where(t => !dictionary.Contains(t)), .. dictionary],
        };
        var transcriber = makeTranscriber(s);
        // 音声の変換（WAV）も UI スレッドで行わない
        return Task.Run(() => transcriber.TranscribeAsync(audio, request, ct), ct);
    }

    /// 整形済みテキスト、AI 整形を諦めて簡易整形にしたときの警告、AI を通さずに整えた文を返す
    Task<Polisher.Output> PolishAsync(string raw, Job job, AppSettings s, AppContextInfo ctx, SurroundingText? surrounding,
        MailReplyContext? reply, CancellationToken ct)
    {
        var preset = s.StyleFor(ctx.Category);
        var request = new PolishRequest
        {
            Transcript = raw,
            Mode = job.Mode,
            SourceLanguages = s.DictationLanguages,
            TargetLanguage = job.Mode == Mode.Translate ? job.TargetLanguage ?? s.CurrentTranslationTarget : null,
            AppName = ctx.AppName,
            Category = ctx.Category,
            StyleDescription = preset.StyleDescription(ctx.Category),
            PersonalStyle = preset == StylePreset.Auto && s.PersonalizationEnabled ? services.Personalization.Profile.PromptDescription(ctx.Category) : null,
            Vocabulary = services.Dictionary.Terms,
            Corrections = s.PersonalizationEnabled ? services.Personalization.Corrections : [],
            Aliases = services.Dictionary.Aliases,
            AliasHints = services.Dictionary.AliasHints,
            Notation = s.JapaneseNotation,
            ChatPunctuation = s.ChatPunctuation,
            Surrounding = surrounding,
            SurroundingInPrompt = s.ShareSurroundingWithLLM,
            AllowsRewording = preset != StylePreset.Auto,
            MailReply = reply,
        };
        var engine = makeEngine(s);
        // 簡易整形の名前の読みで UI スレッドを止めないよう、UI スレッドの外で動かす
        return Task.Run(() => Polisher.Run(request, engine, ct), ct);
    }

    // MARK: - ショートカットからの操作

    /// 最後の結果をもう一度入力する
    public void PasteLast()
    {
        if (phase.Kind is PhaseKind.Recording or PhaseKind.Processing) return;
        if (services.History.LastOutput is not { } text) return;
        _ = PasteLastAsync(text);
    }

    async Task PasteLastAsync(string text)
    {
        try
        {
            if (foreground() is { IsElevatedAboveUs: true })
            {
                ShowMessage(ElevatedMessage, true);
                return;
            }
            if (!await insert(text)) ShowMessage(CopiedMessage, false);
        }
        catch (Exception e)
        {
            Debug.WriteLine($"[Koebumi] 結果の貼り付けに失敗: {e}");
            ShowMessage(ErrorText(e), true);
        }
    }

    /// AI の整形を元に戻す（フェーズ 3。UI Automation で入力した文を確かめてから置き換える）
    public void RevertLast()
    {
        if (phase.Kind is PhaseKind.Recording or PhaseKind.Processing) return;
        ShowMessage(T("AI の整形を元に戻す機能は、Windows 版ではまだ使えません", "Reverting AI cleanup isn't available in the Windows version yet"), false);
    }

    // MARK: - 状態とメッセージ

    void SetPhase(DictationPhase value)
    {
        phase = value;
        if (value.Kind is not (PhaseKind.Recording or PhaseKind.Processing)) level = 0;
        Publish();
    }

    /// HotkeyManager の写しを直して、Changed を出す
    void Publish()
    {
        hotkeys?.SetState(EngineState);
        Changed?.Invoke();
    }

    /// 音声バーの知らせ。エラーは 4 秒、ふつうの知らせは 2 秒で消える（Mac 版と同じ）
    public void ShowMessage(string text, bool isError)
    {
        CancelMessageTimer();
        var message = DictationPhase.Message(text, isError);
        SetPhase(message);
        var cts = messageCts = new CancellationTokenSource();
        _ = HideLater(message, TimeSpan.FromSeconds(isError ? 4 : 2), cts.Token);
    }

    async Task HideLater(DictationPhase message, TimeSpan delay, CancellationToken token)
    {
        try
        {
            await Task.Delay(delay, token);
        }
        catch (OperationCanceledException)
        {
            return;
        }
        if (!disposed && phase == message) SetPhase(DictationPhase.Idle);
    }

    void CancelMessageTimer()
    {
        messageCts?.Cancel();
        messageCts?.Dispose();
        messageCts = null;
    }

    /// 開発用: 音声バーの見た目を確かめるために、状態を直接設定する（Mac 版の setPreviewState）
    internal void SetPreviewState(DictationPhase value, Mode newMode, float newLevel = 0.55f, double elapsedSeconds = 12)
    {
        CancelMessageTimer();
        mode = newMode;
        phase = value;
        level = newLevel;
        elapsed = TimeSpan.FromSeconds(elapsedSeconds);
        Publish();
    }

    static string AskUnavailable => T("Ask anything は、Windows 版ではまだ使えません", "Ask anything isn't available in the Windows version yet");

    static string ElevatedMessage => T("管理者として動いているアプリには入力できません", "Can't type into an app running as administrator");

    static string CopiedMessage => T("入力できなかったので、クリップボードにコピーしました", "Couldn't type it, so it was copied to the clipboard");

    /// 画面に出すエラーの文。認識と整形の失敗（TranscriptionException・LLMException）は、その Message が現在の言語の文になっている
    static string ErrorText(Exception e) => e switch
    {
        HttpRequestException h => T("通信に失敗しました: ", "Network error: ") + (h.InnerException?.Message ?? h.Message),
        _ => e.Message,
    };

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        tick.Stop();
        tick.Tick -= OnTick;
        recorder.Level -= OnRecorderLevel;
        recorder.Error -= OnRecorderError;
        if (hotkeys is not null)
        {
            hotkeys.CommandReceived -= Handle;
            hotkeys.StateProvider = null;
        }
        processingCts?.Cancel();
        CancelMessageTimer();
        if (recorder.IsRecording) recorder.Stop();
    }
}
