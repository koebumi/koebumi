using System.Windows;
using Koebumi.Core;
using static Koebumi.App.SettingsUi;

namespace Koebumi.App;

/// 整形（AI）: Claude・OpenAI 互換（OpenAI・Groq・OpenRouter・Gemini・Ollama・LM Studio・カスタム）・整形しない
internal sealed class PolishPage : SettingsPage
{
    public PolishPage(SettingsWindow host) : base(host) { }

    public override string Title => T("整形（AI）", "Polish (AI)");
    public override string Glyph => "\uE70F";

    protected override void Build()
    {
        var s = S;
        AddHeader(T("フィラーを除き、文章を整えます。OpenAI のキーが 1 つあれば、音声認識と整形の両方が動きます。自分の PC で動かすモデル（Ollama・LM Studio）も使えます。",
                    "Removes fillers and polishes your writing. One OpenAI key covers both speech recognition and polishing. Models on this PC (Ollama, LM Studio) work too."));

        var rows = new List<UIElement?>
        {
            Row(T("エンジン", "Engine"), T("フィラーを除き、文章を整えます", "Removes fillers and polishes your writing"),
                Combo(Enum.GetValues<LLMProvider>(), s.LlmProvider, EngineTitle, p => { Update(x => x.LlmProvider = p); RefreshSoon(); }, 280)),
        };
        switch (s.LlmProvider)
        {
            case LLMProvider.Claude:
                rows.AddRange(ClaudeRows(s));
                break;
            case LLMProvider.OpenAICompatible:
                rows.AddRange(CompatRows(s));
                break;
            default:
                rows.Add(Row(T("簡易整形のみ", "Basic cleanup only"),
                    T("フィラー除去などの簡易整形だけを行います。翻訳と Ask anything は使えません。", "Only basic filler removal. Translation and Ask anything are unavailable.")));
                break;
        }
        Add(Group([.. rows]), 20);

        if (s.LlmProvider != LLMProvider.None && s.LlmRunsLocally)
        {
            Add(Callout("\uE72E", T("整形はこの PC の中で処理するので、文章は PC の外に出ません。", "Polishing runs on this PC, so your text never leaves it.")), 14);
        }
        Add(Footnote(T("API キーは Windows の資格情報マネージャーに保存されます。音声とテキストは選んだサービスにだけ送られます。",
                       "API keys are stored in Windows Credential Manager. Audio and text are sent only to the services you choose."), "\uE8D7"), 14);
    }

    /// ドロップダウンに出す名前（Core の Title は、使えるサービスを並べて長い）
    static string EngineTitle(LLMProvider p) => p switch
    {
        LLMProvider.OpenAICompatible => T("OpenAI 互換（OpenAI・Groq・Ollama など）", "OpenAI-compatible (OpenAI, Groq, Ollama…)"),
        LLMProvider.None => T("整形しない", "None (insert raw transcript)"),
        _ => p.Title,
    };

    IEnumerable<UIElement> ClaudeRows(AppSettings s)
    {
        yield return Row("Anthropic API key",
            T("Claude Max・Team プランには毎月 API クレジットが付きます。claude.ai の設定 > Billing の API credits で Console の組織をつなぎ、その組織で作ったキーを入れると、クレジットから払えます。",
              "Claude Max and Team plans include monthly API credits. Link a Console organization under API credits in claude.ai Settings > Billing, then enter a key from that organization."),
            ApiKeyField(AppSettings.ClaudeKeyAccount));

        // 一覧にないモデル名が設定にあるときも、選択を残す
        var models = ClaudeModels.All.ToList();
        if (!models.Contains(s.ClaudeModel)) models.Add(s.ClaudeModel);
        yield return Row(T("モデル", "Model"), null,
            Combo(models, s.ClaudeModel, ClaudeModels.Title, m => Update(x => x.ClaudeModel = m), 220));

        yield return ToggleRow(T("Ask anything で Web 検索を使う", "Use web search in Ask anything"),
            T("最新の情報が必要な質問に、検索結果を使って答えます", "Answers questions that need fresh information using search results"),
            s.WebSearch, on => Update(x => x.WebSearch = on));
    }

    IEnumerable<UIElement> CompatRows(AppSettings s)
    {
        var service = s.CompatService;
        string raw = Storage.Raw(service);
        yield return Row(T("サービス", "Service"), null,
            Combo(Enum.GetValues<CompatService>(), service, c => c.Title, c => { Update(x => x.CompatService = c); RefreshSoon(); }, 220));

        // Ollama と LM Studio はキーが要らないので、欄を出さない。カスタムのサーバーにはキーが要ることがあるので、任意の欄を出す
        if (service is not (CompatService.Ollama or CompatService.LMStudio))
        {
            yield return Row(T("API キー", "API key") + (service.RequiresKey ? "" : T("（任意）", " (optional)")), null, ApiKeyField(service.KeyAccount));
        }
        yield return Row(T("モデル", "Model"), T("サービスで使えるモデル名に書き換えてください", "Use a model name your service offers"),
            Field(s.CompatModels.GetValueOrDefault(raw, ""), service.DefaultModel, v => Update(x => Set(x.CompatModels, raw, v))));
        yield return Row(T("ベース URL", "Base URL"), T("空にすると既定の URL を使います", "Leave empty to use the default URL"),
            Field(s.CompatBaseURLs.GetValueOrDefault(raw, ""), service.DefaultBaseURL, v => Update(x => Set(x.CompatBaseURLs, raw, v)), 300));
    }

    static void Set(Dictionary<string, string> map, string key, string value)
    {
        if (value.Length == 0) map.Remove(key);
        else map[key] = value;
    }
}
