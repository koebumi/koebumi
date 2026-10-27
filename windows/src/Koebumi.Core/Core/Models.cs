using System.Text.Json.Serialization;

namespace Koebumi.Core;

/// 3 つの操作: ディクテーション / 翻訳 / Ask anything
public enum Mode { Dictate, Translate, Ask }

/// 入力先アプリの種類。アプリごとのトーン調整に使う。
public enum AppCategory { Email, Chat, Document, Code, Ai, Other }

public enum StylePreset { Auto, Business, Formal, Neutral, Casual }

public enum Retention { Forever, Year, Month, Week, Day, Never }

public enum Appearance { System, Light, Dark }

/// 音声認識エンジン。Windows 版は OpenAI 互換の API だけを使う
public enum STTProvider
{
    [JsonStringEnumMemberName("openai")] OpenAI,
    [JsonStringEnumMemberName("groq")] Groq,
    [JsonStringEnumMemberName("custom")] Custom,
}

/// テキスト整形・翻訳・Ask に使う LLM
public enum LLMProvider
{
    [JsonStringEnumMemberName("claude")] Claude,
    [JsonStringEnumMemberName("openAICompatible")] OpenAICompatible,
    [JsonStringEnumMemberName("none")] None,
}

/// OpenAI 互換 API のプリセット。ベース URL と既定モデルを埋めるだけで、どれも書き換え可能。
public enum CompatService
{
    [JsonStringEnumMemberName("openai")] OpenAI,
    [JsonStringEnumMemberName("groq")] Groq,
    [JsonStringEnumMemberName("openrouter")] OpenRouter,
    [JsonStringEnumMemberName("gemini")] Gemini,
    [JsonStringEnumMemberName("ollama")] Ollama,
    [JsonStringEnumMemberName("lmstudio")] LMStudio,
    [JsonStringEnumMemberName("custom")] Custom,
}

public static class ClaudeModels
{
    public const string Opus = "claude-opus-5-5";
    public const string Sonnet = "claude-sonnet-5-5";
    public const string Haiku = "claude-haiku-5-5";

    public static readonly string[] All = [Opus, Sonnet, Haiku];

    public static string Title(string model) => model switch
    {
        Opus => "Claude Opus 5.5",
        Sonnet => "Claude Sonnet 5.5",
        Haiku => T("Claude Haiku 5.5（最速）", "Claude Haiku 5.5 (fastest)"),
        _ => model,
    };
}

public static class ModelExtensions
{
    extension(Mode mode)
    {
        public string Title => mode switch
        {
            Mode.Dictate => T("ディクテーション", "Dictate"),
            Mode.Translate => T("翻訳", "Translate"),
            _ => "Ask anything",
        };
    }

    extension(AppCategory category)
    {
        public string Title => category switch
        {
            AppCategory.Email => T("メール", "Email"),
            AppCategory.Chat => T("チャット", "Chat"),
            AppCategory.Document => T("ドキュメント・メモ", "Docs & notes"),
            AppCategory.Code => T("コーディング", "Coding"),
            AppCategory.Ai => T("AI チャット", "AI chat"),
            _ => T("その他", "Other"),
        };

        /// 既定のトーン（パーソナライズ前）
        public string DefaultStyleDescription => category switch
        {
            AppCategory.Email => "Polished and polite email prose with proper greetings preserved; in Japanese use appropriate keigo (です/ます).",
            AppCategory.Chat => "Casual, conversational chat message. Short sentences. No greeting or sign-off unless spoken. In Japanese keep the speaker's casual/polite level.",
            AppCategory.Document => "Clear, well-structured writing. Use paragraphs and lists where the speaker enumerates.",
            AppCategory.Code => "Concise technical writing. Keep code identifiers, file names, commands and technical terms verbatim (use backticks only if the speaker clearly means code).",
            AppCategory.Ai => "A clear, well-organized prompt for an AI assistant. Preserve every requirement the speaker mentions.",
            _ => "Natural, clean writing that matches how the speaker talks.",
        };
    }

    extension(StylePreset preset)
    {
        public string Title => preset switch
        {
            StylePreset.Auto => T("自動（パーソナライズ）", "Auto (personalized)"),
            StylePreset.Business => T("ビジネス敬語", "Business formal"),
            StylePreset.Formal => T("フォーマル", "Formal"),
            StylePreset.Neutral => T("ニュートラル", "Neutral"),
            _ => T("カジュアル", "Casual"),
        };

        public string? PromptDescription => preset switch
        {
            StylePreset.Auto => null,
            StylePreset.Business => "Very formal business register. In Japanese, use business keigo with です/ます: 尊敬語 for other people's actions and 謙譲語 for the speaker's own (見る→ご覧になる/拝見する, 言う→おっしゃる/申し上げる, 行く・来る→いらっしゃる/伺う・参る, する→なさる/いたす, もらう→いただく), and avoid double honorifics such as おっしゃられる or ご覧になられる. Example: 社長が食べたいって言ってたお菓子、買っときました → 社長が召し上がりたいとおっしゃっていたお菓子を買っておきました。",
            StylePreset.Formal => "Formal and polite register (in Japanese: です/ます with natural 丁寧語・敬語).",
            StylePreset.Neutral => "Neutral, plain register.",
            _ => "Casual, friendly register (in Japanese: くだけた口調 when the speaker uses it).",
        };

        /// アプリの種類の既定トーンに、ユーザーが選んだ言葉づかいを重ねた指示
        public string StyleDescription(AppCategory category)
        {
            if (preset.PromptDescription is not { } p) return category.DefaultStyleDescription;
            return category.DefaultStyleDescription
                + " The user chose this register for this kind of app, and it overrides the register above: " + p
                + " Rewrite sentence endings and honorifics to this register even if the speaker talked more casually, without changing the content.";
        }
    }

    extension(Retention retention)
    {
        public string Title => retention switch
        {
            Retention.Forever => T("無期限", "Forever"),
            Retention.Year => T("1年", "1 year"),
            Retention.Month => T("1か月", "1 month"),
            Retention.Week => T("1週間", "1 week"),
            Retention.Day => T("24時間", "24 hours"),
            _ => T("保存しない", "Never"),
        };

        /// 保存期間。null は無期限。
        public TimeSpan? Interval => retention switch
        {
            Retention.Forever => null,
            Retention.Year => TimeSpan.FromDays(365),
            Retention.Month => TimeSpan.FromDays(30),
            Retention.Week => TimeSpan.FromDays(7),
            Retention.Day => TimeSpan.FromDays(1),
            _ => TimeSpan.Zero,
        };
    }

    extension(Appearance appearance)
    {
        public string Title => appearance switch
        {
            Appearance.System => T("システムに合わせる", "System"),
            Appearance.Light => T("ライト", "Light"),
            _ => T("ダーク", "Dark"),
        };
    }

    extension(STTProvider provider)
    {
        public string Title => provider switch
        {
            STTProvider.OpenAI => "OpenAI",
            STTProvider.Groq => "Groq",
            _ => T("カスタム（OpenAI 互換）", "Custom (OpenAI-compatible)"),
        };

        /// API キーを保存する名前
        public string KeyAccount => provider switch
        {
            STTProvider.OpenAI => "openai",
            STTProvider.Groq => "groq",
            _ => "custom-stt",
        };

        public string DefaultBaseURL => provider switch
        {
            STTProvider.OpenAI => "https://api.openai.com/v1",
            STTProvider.Groq => "https://api.groq.com/openai/v1",
            _ => "http://localhost:8000/v1",
        };

        public string DefaultModel => provider switch
        {
            STTProvider.OpenAI => "gpt-4o-transcribe",
            STTProvider.Groq => "whisper-large-v3-turbo",
            _ => "whisper-1",
        };
    }

    extension(LLMProvider provider)
    {
        public string Title => provider switch
        {
            LLMProvider.Claude => "Claude (Anthropic)",
            LLMProvider.OpenAICompatible => T("OpenAI 互換（OpenAI・Groq・OpenRouter・Gemini・Ollama・LM Studio など）", "OpenAI-compatible (OpenAI, Groq, OpenRouter, Gemini, Ollama, LM Studio…)"),
            _ => T("整形しない（認識結果をそのまま入力）", "None (insert raw transcript)"),
        };
    }

    extension(CompatService service)
    {
        public string Title => service switch
        {
            CompatService.OpenAI => "OpenAI",
            CompatService.Groq => "Groq",
            CompatService.OpenRouter => "OpenRouter",
            CompatService.Gemini => "Google Gemini",
            CompatService.Ollama => T("Ollama（この PC）", "Ollama (this PC)"),
            CompatService.LMStudio => T("LM Studio（この PC）", "LM Studio (this PC)"),
            _ => T("カスタム", "Custom"),
        };

        public string KeyAccount => service switch
        {
            CompatService.OpenAI => "openai",
            CompatService.Groq => "groq",
            CompatService.OpenRouter => "openrouter",
            CompatService.Gemini => "gemini",
            CompatService.Ollama => "ollama",
            CompatService.LMStudio => "lmstudio",
            _ => "custom-llm",
        };

        public string DefaultBaseURL => service switch
        {
            CompatService.OpenAI => "https://api.openai.com/v1",
            CompatService.Groq => "https://api.groq.com/openai/v1",
            CompatService.OpenRouter => "https://openrouter.ai/api/v1",
            CompatService.Gemini => "https://generativelanguage.googleapis.com/v1beta/openai",
            CompatService.Ollama => "http://localhost:11434/v1",
            CompatService.LMStudio => "http://localhost:1234/v1",
            _ => "http://localhost:8080/v1",
        };

        public string DefaultModel => service switch
        {
            CompatService.OpenAI => "gpt-5-mini",
            CompatService.Groq => "openai/gpt-oss-120b",
            CompatService.OpenRouter => "openai/gpt-5-mini",
            CompatService.Gemini => "gemini-2.5-flash",
            CompatService.Ollama => "qwen3:8b",
            CompatService.LMStudio => "local-model",
            _ => "local-model",
        };

        public bool RequiresKey => service is not (CompatService.Ollama or CompatService.LMStudio or CompatService.Custom);
    }
}
