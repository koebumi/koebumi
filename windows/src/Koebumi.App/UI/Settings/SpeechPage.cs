using System.Windows;
using System.Windows.Controls;
using Koebumi.Core;
using static Koebumi.App.SettingsUi;

namespace Koebumi.App;

/// 音声認識: OpenAI・Groq・カスタム（OpenAI 互換）から選び、キー・モデル・ベース URL を設定する
internal sealed class SpeechPage : SettingsPage
{
    public SpeechPage(SettingsWindow host) : base(host) { }

    public override string Title => T("音声認識", "Speech recognition");
    public override string Glyph => "\uE720";

    protected override void Build()
    {
        var s = S;
        AddHeader(T("話した声を文字にするサービスを選びます。OpenAI 互換の /audio/transcriptions に音声を送ります。",
                    "Choose the service that turns your voice into text. Audio is sent to an OpenAI-compatible /audio/transcriptions endpoint."));

        var rows = new List<UIElement?>();
        foreach (var provider in Enum.GetValues<STTProvider>())
        {
            rows.Add(ProviderRow(provider, provider == s.SttProvider));
            if (provider == s.SttProvider) rows.Add(Details(provider, s));
        }
        Add(Group([.. rows]), 20);

        if (s.SttRunsLocally)
        {
            Add(Callout("\uE72E", T("このサーバーは PC の中（localhost）にあるので、音声は PC の外に出ません。", "This server runs on this PC (localhost), so your audio never leaves it.")), 14);
        }
        Add(Footnote(T("API キーは Windows の資格情報マネージャーに保存します。URL を localhost にした自分のサーバー（whisper.cpp・speaches・LocalAI など）を「カスタム」に指定すれば、音声は PC の外に出ません。",
                       "API keys are stored in Windows Credential Manager. Point “Custom” at your own server on localhost (whisper.cpp, speaches, LocalAI…) and audio never leaves this PC."), "\uE8D7"), 14);
    }

    /// 選択の丸と、サービスの名前・説明
    UIElement ProviderRow(STTProvider provider, bool selected)
    {
        var grid = new Grid { MinHeight = 64 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(46) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        var radio = RadioMark(selected);
        radio.SetValue(FrameworkElement.MarginProperty, new Thickness(16, 15, 0, 0));
        radio.SetValue(FrameworkElement.VerticalAlignmentProperty, VerticalAlignment.Top);
        grid.Children.Add(radio);

        var text = new StackPanel { Margin = new Thickness(0, 13, 16, 13), VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Label(provider.Title, 14, K.Text, FontWeights.Medium));
        var summary = Label(Summary(provider), 12.5, K.TextSecondary);
        summary.Margin = new Thickness(0, 3, 0, 0);
        text.Children.Add(summary);
        var details = Label(Facts(provider), 12, K.TextTertiary);
        details.Margin = new Thickness(0, 4, 0, 0);
        text.Children.Add(details);
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);

        return Hoverable(grid, () =>
        {
            if (provider == S.SttProvider) return;
            Update(x => x.SttProvider = provider);
            RefreshSoon();
        });
    }

    static string Summary(STTProvider provider) => provider switch
    {
        STTProvider.OpenAI => T("OpenAI の gpt-4o-transcribe で認識します。", "Transcribes with OpenAI's gpt-4o-transcribe."),
        STTProvider.Groq => T("Groq の上で Whisper Large v3 Turbo を動かします。", "Runs Whisper Large v3 Turbo on Groq."),
        _ => T("OpenAI 互換の /audio/transcriptions に送ります。whisper.cpp などの自分のサーバーも使えます。",
               "Sends audio to any OpenAI-compatible /audio/transcriptions endpoint, such as your own whisper.cpp server."),
    };

    static string Facts(STTProvider provider) => provider switch
    {
        STTProvider.OpenAI => "OpenAI  ·  " + T("API キーが必要", "API key required"),
        STTProvider.Groq => "Groq  ·  " + T("API キーが必要", "API key required"),
        _ => T("URL を指定", "Your own URL") + "  ·  " + T("API キーは任意", "API key optional"),
    };

    /// 選んだサービスのすぐ下に出す設定
    UIElement Details(STTProvider provider, AppSettings s)
    {
        string raw = Storage.Raw(provider);
        var optional = provider.RequiresKey ? "" : T("（任意）", " (optional)");
        // 選んだ行の下に、少し引っ込めて置く
        var rows = DividedStack(
            Row(T("API キー", "API key") + optional, null, ApiKeyField(provider.KeyAccount)),
            Row(T("モデル", "Model"), null,
                Field(s.SttModels.GetValueOrDefault(raw, ""), provider.DefaultModel, v => Update(x => Set(x.SttModels, raw, v)))),
            Row(T("ベース URL", "Base URL"), T("空にすると既定の URL を使います", "Leave empty to use the default URL"),
                Field(s.SttBaseURLs.GetValueOrDefault(raw, ""), provider.DefaultBaseURL, v => Update(x => Set(x.SttBaseURLs, raw, v)), 300)));
        rows.Margin = new Thickness(46, 0, 0, 0);
        var frame = new StackPanel();
        frame.Children.Add(new Border { Height = 1 }.Brush(Border.BackgroundProperty, K.Divider));
        frame.Children.Add(rows);
        return frame;
    }

    static void Set(Dictionary<string, string> map, string key, string value)
    {
        if (value.Length == 0) map.Remove(key);
        else map[key] = value;
    }
}
