using System.Text.Json.Serialization;

namespace Koebumi.Core;

public sealed record CategoryProfile(int Formality, int Verbosity, string Notes);

/// 学習した文体。内容そのものは保存せず、抽象的な傾向だけを持つ。
public sealed record StyleProfile
{
    public string General { get; init; } = "";
    /// AppCategory の rawValue（"email" など）→ 傾向
    public IReadOnlyDictionary<string, CategoryProfile> Categories { get; init; } = new Dictionary<string, CategoryProfile>();
    public int SamplesAnalyzed { get; init; }
    [JsonConverter(typeof(Iso8601DateConverter))]
    public DateTimeOffset? UpdatedAt { get; init; }

    public string? PromptDescription(AppCategory category)
    {
        var parts = new List<string>();
        if (Categories.TryGetValue(Storage.Raw(category), out var c))
        {
            parts.Add($"formality {c.Formality}/100, verbosity {c.Verbosity}/100. {c.Notes}");
        }
        if (General.Length > 0) parts.Add(General);
        return parts.Count == 0 ? null : string.Join(" ", parts);
    }
}

/// ユーザーが出力を直した例（履歴のフィードバックから作る）
public sealed record Correction(string Original, string Preferred);

public sealed class PersonalizationData
{
    public StyleProfile Profile { get; set; } = new();
    public List<StyleSample> Pending { get; set; } = [];
    public List<Correction> Corrections { get; set; } = [];
}

/// 文体の学習と、ユーザーが直した例の記録。ファイル（personalization.json）に保存する。
/// どのスレッドからでも呼べる。Changed は、変更したスレッドで（ロックを外してから）呼ぶので、画面の更新は呼び出し側で UI スレッドに移す
public sealed class PersonalizationStore
{
    public const string FileName = "personalization.json";
    /// この数だけサンプルが溜まったら文体を学習し、サンプルは捨てる
    public const int BatchSize = 6;
    /// 学習の進み具合を 100% とみなすサンプル数
    public const int FullProgressSamples = 60;

    readonly object _gate = new();
    /// null ならファイルに読み書きしない（テスト用）
    readonly string? _file;
    /// 学習の時間の上限。普段は数秒で終わる。
    readonly TimeSpan _timeout;
    StyleProfile _profile;
    readonly List<StyleSample> _pending;
    readonly List<Correction> _corrections;
    string? _lastError;
    bool _isAnalyzing;
    /// 学習に失敗したら、サンプルがこの数まで溜まるまで自動では学習し直さない（話すたびに失敗する学習を繰り返さない）
    int _nextAutoAnalysis = BatchSize;
    Task _analysisTask = Task.CompletedTask;
    CancellationTokenSource? _analysisCancellation;

    /// 学習した文体・直した例・学習の状態が変わった
    public event EventHandler? Changed;

    /// folder が null なら %APPDATA%\Koebumi（Storage.Root）。inMemory ならファイルに読み書きしない
    public PersonalizationStore(string? folder = null, bool inMemory = false, TimeSpan? timeout = null)
    {
        _timeout = timeout ?? TimeSpan.FromSeconds(30);
        PersonalizationData data = new();
        if (!inMemory)
        {
            folder ??= Storage.Root;
            Directory.CreateDirectory(folder);
            _file = Path.Combine(folder, FileName);
            data = Storage.LoadAt<PersonalizationData>(_file) ?? new PersonalizationData();
        }
        _profile = data.Profile;
        _pending = data.Pending;
        _corrections = data.Corrections;
    }

    /// 呼んだ時点の文体。書き換えない（学習のたびに新しいものに替わる）
    public StyleProfile Profile { get { lock (_gate) return _profile; } }

    public IReadOnlyList<Correction> Corrections { get { lock (_gate) return [.. _corrections]; } }

    public int PendingCount { get { lock (_gate) return _pending.Count; } }

    public bool IsAnalyzing { get { lock (_gate) return _isAnalyzing; } }

    /// 学習の失敗の理由（成功すると消える）
    public string? LastError { get { lock (_gate) return _lastError; } }

    public double Progress
    {
        get
        {
            lock (_gate) return Math.Min(1.0, (double)(_profile.SamplesAnalyzed + _pending.Count) / FullProgressSamples);
        }
    }

    public void AddSample(StyleSample sample, ILLMEngine? engine)
    {
        if (ContextText.Count(sample.Text) < 8) return;
        bool start;
        lock (_gate)
        {
            _pending.Add(sample);
            Save();
            start = engine is not null && _pending.Count >= _nextAutoAnalysis;
        }
        Changed?.Invoke(this, EventArgs.Empty);
        if (start) StartAnalysis(engine!);
    }

    public void AddCorrection(Correction c)
    {
        if (c.Original == c.Preferred) return;
        lock (_gate)
        {
            _corrections.Add(c);
            if (_corrections.Count > 30) _corrections.RemoveRange(0, _corrections.Count - 30);
            Save();
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// 学習して、終わるまで待つ（すでに学習中なら、その学習の終わりを待つ）
    public async Task AnalyzeAsync(ILLMEngine engine)
    {
        StartAnalysis(engine);
        Task running;
        lock (_gate) running = _analysisTask;
        await running;
    }

    /// 学習を裏で始める
    public void StartAnalysis(ILLMEngine engine)
    {
        lock (_gate)
        {
            if (_isAnalyzing || _pending.Count == 0) return;
            _isAnalyzing = true;
            var cancellation = _analysisCancellation = new CancellationTokenSource();
            _analysisTask = Task.Run(() => RunAsync(engine, cancellation));
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// 学習を取り消す。録音を始めたときに呼び、その録音の整形を学習の後ろで待たせない。取り消した学習は次に話したときにやり直す。
    public void CancelAnalysis()
    {
        lock (_gate) _analysisCancellation?.Cancel();
    }

    async Task RunAsync(ILLMEngine engine, CancellationTokenSource cancellation)
    {
        try
        {
            List<StyleSample> batch;
            StyleProfile current;
            lock (_gate)
            {
                batch = [.. _pending];
                current = _profile;
            }
            try
            {
                var result = await WithTimeout(_timeout, token => engine.AnalyzeStyleAsync(batch, current, token), cancellation.Token);
                lock (_gate)
                {
                    ApplyCore(result, batch.Count);
                    _pending.RemoveRange(0, Math.Min(batch.Count, _pending.Count));
                    _nextAutoAnalysis = BatchSize;
                    _lastError = null;
                    Save();
                }
            }
            catch (Exception e)
            {
                if (cancellation.IsCancellationRequested) return;
                lock (_gate)
                {
                    _lastError = e.Message;
                    _nextAutoAnalysis = _pending.Count + BatchSize;
                }
            }
        }
        finally
        {
            lock (_gate)
            {
                _isAnalyzing = false;
                _analysisCancellation = null;
            }
            cancellation.Dispose();
            Changed?.Invoke(this, EventArgs.Empty);
        }
    }

    /// body が limit までに終わらなければ取り消して、時間切れのエラーを投げる
    static async Task<TResult> WithTimeout<TResult>(TimeSpan limit, Func<CancellationToken, Task<TResult>> body, CancellationToken cancellationToken)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var work = body(linked.Token);
        var timer = Task.Delay(limit, linked.Token);
        var finished = await Task.WhenAny(work, timer);
        if (finished == work)
        {
            linked.Cancel();  // 待っていたタイマーを止める
            return await work;
        }
        cancellationToken.ThrowIfCancellationRequested();
        linked.Cancel();
        // 取り消しに応えない処理が後で失敗しても、見落とした例外にしない
        _ = work.ContinueWith(t => _ = t.Exception, TaskContinuationOptions.OnlyOnFaulted);
        throw LLMException.Unavailable(T("文体の学習が時間内に終わりませんでした", "Style learning timed out"));
    }

    public void Apply(StyleAnalysis result, int sampleCount)
    {
        lock (_gate)
        {
            ApplyCore(result, sampleCount);
            Save();
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// ロックの中で呼ぶ
    void ApplyCore(StyleAnalysis result, int sampleCount)
    {
        var categories = new Dictionary<string, CategoryProfile>(_profile.Categories);
        foreach (var c in result.Categories)
        {
            if (!Enum.GetValues<AppCategory>().Any(known => Storage.Raw(known) == c.Category)) continue;
            categories[c.Category] = new CategoryProfile(Math.Clamp(c.Formality, 0, 100), Math.Clamp(c.Verbosity, 0, 100), c.Notes);
        }
        _profile = _profile with
        {
            General = result.General.Length > 0 ? result.General : _profile.General,
            Categories = categories,
            SamplesAnalyzed = _profile.SamplesAnalyzed + sampleCount,
            UpdatedAt = DateTimeOffset.UtcNow,
        };
    }

    public void Reset()
    {
        lock (_gate)
        {
            _profile = new StyleProfile();
            _pending.Clear();
            _corrections.Clear();
            Save();
        }
        Changed?.Invoke(this, EventArgs.Empty);
    }

    /// ロックの中で呼ぶ
    void Save()
    {
        if (_file is null) return;
        Storage.SaveAt(new PersonalizationData { Profile = _profile, Pending = [.. _pending], Corrections = [.. _corrections] }, _file);
    }
}
