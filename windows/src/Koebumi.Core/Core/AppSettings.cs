using System.Text.Json;
using System.Text.Json.Serialization;

namespace Koebumi.Core;

/// 設定。%APPDATA%\Koebumi\settings.json に Mac 版と同じ形で保存する（Mac 版にしかない項目は持たない）。
/// 新しい項目を足しても古い設定ファイルを読めるよう、欠けたキーは既定値で埋める（TolerantConverter）
[JsonConverter(typeof(TolerantConverter<AppSettings>))]
public sealed class AppSettings
{
    public const string FileName = "settings.json";

    // 一般
    public UILanguage UiLanguage { get; set; } = L10n.SystemDefault;
    public Appearance Appearance { get; set; } = Appearance.System;
    public bool LaunchAtLogin { get; set; }
    public bool OnboardingCompleted { get; set; }

    // ショートカット（各操作に複数登録できる）
    public List<Shortcut> DictateShortcuts { get; set; } = [Shortcut.CtrlWin];
    public List<Shortcut> TranslateShortcuts { get; set; } = [Shortcut.CtrlWinShift];
    public List<Shortcut> AskShortcuts { get; set; } = [Shortcut.CtrlWinSpace];
    public List<Shortcut> PasteLastShortcuts { get; set; } = [Shortcut.CtrlAltV];
    public List<Shortcut> RevertLastShortcuts { get; set; } = [Shortcut.CtrlAltZ];

    // オーディオ
    /// null は自動（Windows の既定の録音デバイス）
    public string? MicrophoneId { get; set; }
    public bool InteractionSounds { get; set; } = true;
    public bool MuteWhileDictating { get; set; }

    // 言語
    public List<string> DictationLanguages { get; set; } = [L10n.SystemDefault == UILanguage.Ja ? "ja-JP" : "en-US"];
    public string? ActiveDictationLanguage { get; set; }
    public List<string> TranslationTargets { get; set; } = ["en-US"];
    public string? ActiveTranslationTarget { get; set; }

    // 音声認識（BYOK）
    public STTProvider SttProvider { get; set; } = STTProvider.OpenAI;
    /// provider の rawValue → model
    public Dictionary<string, string> SttModels { get; set; } = [];
    /// provider の rawValue → base URL
    public Dictionary<string, string> SttBaseURLs { get; set; } = [];

    // テキスト整形（BYOK）。OpenAI のキーが 1 つあれば、音声認識と整形の両方が動く
    public LLMProvider LlmProvider { get; set; } = LLMProvider.OpenAICompatible;
    public string ClaudeModel { get; set; } = ClaudeModels.Haiku;
    public CompatService CompatService { get; set; } = CompatService.OpenAI;
    /// service の rawValue → model
    public Dictionary<string, string> CompatModels { get; set; } = [];
    /// service の rawValue → base URL
    public Dictionary<string, string> CompatBaseURLs { get; set; } = [];
    public bool WebSearch { get; set; } = true;

    // 履歴・プライバシー
    public Retention HistoryRetention { get; set; } = Retention.Forever;
    /// Mac 版の既定はオン。Windows 版は履歴の画面（フェーズ 2）ができるまで、消す手段がないのでオフ
    public bool KeepAudio { get; set; }
    public bool KeepResultInClipboard { get; set; }

    // パーソナライズ・辞書
    public bool PersonalizationEnabled { get; set; } = true;
    public bool AutoAddDictionary { get; set; } = true;
    /// AppCategory の rawValue → preset
    public Dictionary<string, StylePreset> CategoryStyles { get; set; } = [];
    /// exe 名（小文字。例: "slack.exe"）→ category
    public Dictionary<string, AppCategory> AppCategoryOverrides { get; set; } = [];
    public JapaneseNotation JapaneseNotation { get; set; } = new();
    /// 「チャット」に分類したアプリでの句読点（どの言語にも使う）
    public ChatPunctuation ChatPunctuation { get; set; } = ChatPunctuation.NoPunctuation;
    /// Mac 版の既定は LocalOnly。Windows 版は、UI Automation で読める範囲をアプリごとに確かめる（フェーズ 3）までオフ
    public ContextAwareness ContextAwareness { get; set; } = ContextAwareness.Off;
    /// メールでは、返信先のメールに合わせて書き出しの挨拶と相手の敬称を直す。
    /// Mac 版の既定はオン。Windows 版は、メールのアプリで返信先を読めるか確かめる（フェーズ 3）までオフ
    public bool MailReplyStyle { get; set; }
    /// 呼び出す言葉だけを話すと入力する定型文（署名・挨拶など）
    public List<Snippet> Snippets { get; set; } = [];

    public List<Shortcut> ShortcutsFor(Mode mode) => mode switch
    {
        Mode.Dictate => DictateShortcuts,
        Mode.Translate => TranslateShortcuts,
        _ => AskShortcuts,
    };

    public void SetShortcuts(List<Shortcut> list, Mode mode)
    {
        switch (mode)
        {
            case Mode.Dictate: DictateShortcuts = list; break;
            case Mode.Translate: TranslateShortcuts = list; break;
            default: AskShortcuts = list; break;
        }
    }

    [JsonIgnore]
    public string CurrentDictationLanguage =>
        ActiveDictationLanguage is { } a && DictationLanguages.Contains(a) ? a : DictationLanguages.FirstOrDefault() ?? "ja-JP";

    [JsonIgnore]
    public string CurrentTranslationTarget =>
        ActiveTranslationTarget is { } a && TranslationTargets.Contains(a) ? a : TranslationTargets.FirstOrDefault() ?? "en-US";

    public string SttModel(STTProvider p) => Value(SttModels, Storage.Raw(p), p.DefaultModel);
    public string SttBaseURL(STTProvider p) => Value(SttBaseURLs, Storage.Raw(p), p.DefaultBaseURL);
    public string CompatModel(CompatService s) => Value(CompatModels, Storage.Raw(s), s.DefaultModel);
    public string CompatBaseURL(CompatService s) => Value(CompatBaseURLs, Storage.Raw(s), s.DefaultBaseURL);

    static string Value(Dictionary<string, string> map, string key, string fallback) =>
        map.TryGetValue(key, out var v) && !string.IsNullOrEmpty(v) ? v : fallback;

    public StylePreset StyleFor(AppCategory category) =>
        CategoryStyles.TryGetValue(Storage.Raw(category), out var p) ? p : StylePreset.Auto;

    /// Claude の API キーを保存する名前
    public const string ClaudeKeyAccount = "anthropic";

    /// 整形のエンジンが使うキーの名前（資格情報の名前）。キーが要らない設定なら null
    [JsonIgnore]
    public string? LlmKeyAccount => LlmProvider switch
    {
        LLMProvider.None => null,
        LLMProvider.Claude => ClaudeKeyAccount,
        _ => CompatService.RequiresKey ? CompatService.KeyAccount : null,
    };

    /// 文章の整形がこの PC の中で終わるか（Ollama・LM Studio・localhost のサーバー）
    [JsonIgnore]
    public bool LlmRunsLocally => LlmProvider switch
    {
        LLMProvider.None => true,
        LLMProvider.Claude => false,
        _ => CompatService is CompatService.Ollama or CompatService.LMStudio || IsLocalURL(CompatBaseURL(CompatService)),
    };

    /// 音声認識がこの PC の中で終わるか
    [JsonIgnore]
    public bool SttRunsLocally => IsLocalURL(SttBaseURL(SttProvider));

    /// 画面の文脈を AI 整形のプロンプトに入れてよいか
    [JsonIgnore]
    public bool ShareSurroundingWithLLM =>
        ContextAwareness == ContextAwareness.Always || (ContextAwareness == ContextAwareness.LocalOnly && LlmRunsLocally);

    /// 画面から拾った語を音声認識のヒントに渡してよいか
    [JsonIgnore]
    public bool ShareSurroundingWithSTT =>
        ContextAwareness == ContextAwareness.Always || (ContextAwareness == ContextAwareness.LocalOnly && SttRunsLocally);

    public static bool IsLocalURL(string s)
    {
        if (!Uri.TryCreate(s, UriKind.Absolute, out var uri)) return false;
        var host = uri.Host.ToLowerInvariant().Trim('[', ']');
        return host is "localhost" or "127.0.0.1" or "::1" || host.EndsWith(".local", StringComparison.Ordinal);
    }

    public AppSettings Clone() => JsonSerializer.Deserialize<AppSettings>(JsonSerializer.Serialize(this, Storage.Json), Storage.Json)!;

    /// 中身が同じか（保存するかどうかを決めるのに使う）
    public bool SameAs(AppSettings other) => JsonSerializer.Serialize(this, Storage.Json) == JsonSerializer.Serialize(other, Storage.Json);
}
