using System.Text.Json;
using Koebumi.Core;

namespace Koebumi.Core.Tests;

public class SettingsTests
{
    [Fact]
    public void RoundTripsThroughJson()
    {
        var s = new AppSettings { SttProvider = STTProvider.Groq, ChatPunctuation = ChatPunctuation.Keep };
        s.CategoryStyles[Storage.Raw(AppCategory.Email)] = StylePreset.Business;
        s.Snippets.Add(new Snippet { Trigger = "署名", Text = "矢野" });
        var json = JsonSerializer.Serialize(s, Storage.Json);
        Assert.Contains("\"sttProvider\": \"groq\"", json);
        Assert.Contains("\"email\": \"business\"", json);
        Assert.Contains("\"mods\": [", json);
        var back = JsonSerializer.Deserialize<AppSettings>(json, Storage.Json)!;
        Assert.True(back.SameAs(s));
        Assert.Equal(StylePreset.Business, back.StyleFor(AppCategory.Email));
        Assert.Equal(Shortcut.CtrlWin, back.DictateShortcuts[0]);
    }

    // Mac 版の settingsDecodeFillsMissingKeys: 欠けたキーと読めない値は既定値で埋める
    [Fact]
    public void DecodeFillsMissingKeysAndSkipsBadValues()
    {
        var json = """{"sttProvider":"apple","chatPunctuation":"keep","japaneseNotation":{"punctuation":"commaPeriod","latinSpacing":"bogus"}}""";
        var s = JsonSerializer.Deserialize<AppSettings>(json, Storage.Json)!;
        Assert.Equal(STTProvider.OpenAI, s.SttProvider);
        Assert.Equal(ChatPunctuation.Keep, s.ChatPunctuation);
        Assert.Equal(JapanesePunctuation.CommaPeriod, s.JapaneseNotation.Punctuation);
        Assert.Equal(LatinSpacing.Keep, s.JapaneseNotation.LatinSpacing);
        Assert.True(s.JapaneseNotation.HiraganaForms);
        Assert.Equal([Shortcut.CtrlWin], s.DictateShortcuts);
    }

    // Windows 版だけの既定値。まだ確かめていない機能（画面の文脈・メールの返信先）と、消す画面がない音声の保存はオフ
    [Fact]
    public void UnverifiedFeaturesAreOffByDefault()
    {
        var s = new AppSettings();
        Assert.Equal(ContextAwareness.Off, s.ContextAwareness);
        Assert.False(s.ShareSurroundingWithLLM);
        Assert.False(s.MailReplyStyle);
        Assert.False(s.KeepAudio);
        // 保存してある設定は、そのまま読む
        var saved = JsonSerializer.Deserialize<AppSettings>("""{"contextAwareness":"localOnly","mailReplyStyle":true,"keepAudio":true}""", Storage.Json)!;
        Assert.Equal(ContextAwareness.LocalOnly, saved.ContextAwareness);
        Assert.True(saved.MailReplyStyle);
        Assert.True(saved.KeepAudio);
    }

    [Fact]
    public void LocalEnginesKeepScreenTextOnThisPC()
    {
        var s = new AppSettings { LlmProvider = LLMProvider.OpenAICompatible, CompatService = CompatService.Ollama, ContextAwareness = ContextAwareness.LocalOnly };
        Assert.True(s.LlmRunsLocally);
        Assert.True(s.ShareSurroundingWithLLM);
        Assert.False(s.ShareSurroundingWithSTT);
        s.SttProvider = STTProvider.Custom;
        Assert.True(s.SttRunsLocally);
        s.ContextAwareness = ContextAwareness.Off;
        Assert.False(s.ShareSurroundingWithLLM);
        Assert.True(AppSettings.IsLocalURL("http://127.0.0.1:1234/v1"));
        Assert.False(AppSettings.IsLocalURL("https://api.openai.com/v1"));
    }

    [Fact]
    public void LanguagesTellScripts()
    {
        Assert.True(Languages.IsWritten("明日の会議は4時です", "ja-JP"));
        Assert.False(Languages.IsWritten("The meeting is at four", "ja-JP"));
        Assert.True(Languages.IsWritten("The meeting is at four", "en-US"));
        Assert.Equal("Japanese (Japan)", Languages.EnglishName("ja-JP"));
        Assert.Equal("EN-US", Languages.ShortName("en-US", ["en-US", "en-GB", "ja-JP"]));
        Assert.Equal("JA", Languages.ShortName("ja-JP", ["en-US", "ja-JP"]));
        Assert.True(Languages.IsUnspaced("zh-TW"));
    }

    // カスタムの音声認識だけは、キーなしで動く
    [Fact]
    public void OnlyCustomSpeechWorksWithoutKey()
    {
        Assert.True(STTProvider.OpenAI.RequiresKey);
        Assert.True(STTProvider.Groq.RequiresKey);
        Assert.False(STTProvider.Custom.RequiresKey);
    }

    [Theory]
    [InlineData(LLMProvider.None, CompatService.OpenAI, null)]
    [InlineData(LLMProvider.Claude, CompatService.OpenAI, "anthropic")]
    [InlineData(LLMProvider.OpenAICompatible, CompatService.Groq, "groq")]
    [InlineData(LLMProvider.OpenAICompatible, CompatService.Ollama, null)]
    [InlineData(LLMProvider.OpenAICompatible, CompatService.Custom, null)]
    public void LlmKeyAccountIsNullWhenNoKeyIsNeeded(LLMProvider provider, CompatService service, string? expected)
    {
        var s = new AppSettings { LlmProvider = provider, CompatService = service };
        Assert.Equal(expected, s.LlmKeyAccount);
        Assert.DoesNotContain("llmKeyAccount", JsonSerializer.Serialize(s, Storage.Json));
    }

    // 設定の画面の保存と、Mac 版と同じ形の JSON のキー
    [Fact]
    public void ModelAndBaseURLWritersUseRawValueKeys()
    {
        var s = new AppSettings();
        s.SetSttModel(STTProvider.Groq, "whisper-large-v3");
        s.SetSttBaseURL(STTProvider.Custom, "http://localhost:9000/v1");
        s.SetCompatModel(CompatService.LMStudio, "my-model");
        s.SetCompatBaseURL(CompatService.OpenRouter, "https://example.test/v1");
        Assert.Equal("whisper-large-v3", s.SttModels["groq"]);
        Assert.Equal("http://localhost:9000/v1", s.SttBaseURLs["custom"]);
        Assert.Equal("my-model", s.CompatModels["lmstudio"]);
        Assert.Equal("https://example.test/v1", s.CompatBaseURLs["openrouter"]);
        Assert.Equal("whisper-large-v3", s.SttModel(STTProvider.Groq));
        Assert.Equal("whisper-large-v3", s.SttModelOverride(STTProvider.Groq));
        Assert.Equal("http://localhost:9000/v1", s.SttBaseURLOverride(STTProvider.Custom));
        Assert.Equal("my-model", s.CompatModelOverride(CompatService.LMStudio));
        Assert.Equal("https://example.test/v1", s.CompatBaseURLOverride(CompatService.OpenRouter));
        Assert.Equal("", s.SttModelOverride(STTProvider.OpenAI));
    }

    [Fact]
    public void WritingAnEmptyValueRestoresTheDefault()
    {
        var s = new AppSettings();
        s.SetCompatModel(CompatService.Groq, "my-model");
        s.SetCompatBaseURL(CompatService.Groq, "http://localhost:1/v1");
        s.SetSttModel(STTProvider.OpenAI, "x");
        s.SetSttBaseURL(STTProvider.OpenAI, "http://localhost:2/v1");
        s.SetCompatModel(CompatService.Groq, "");
        s.SetCompatBaseURL(CompatService.Groq, "");
        s.SetSttModel(STTProvider.OpenAI, "");
        s.SetSttBaseURL(STTProvider.OpenAI, "");
        Assert.Empty(s.CompatModels);
        Assert.Empty(s.CompatBaseURLs);
        Assert.Empty(s.SttModels);
        Assert.Empty(s.SttBaseURLs);
        Assert.Equal(CompatService.Groq.DefaultModel, s.CompatModel(CompatService.Groq));
        Assert.Equal(STTProvider.OpenAI.DefaultBaseURL, s.SttBaseURL(STTProvider.OpenAI));
    }

    [Fact]
    public void SetStyleStoresUnderTheCategoryRawValue()
    {
        var s = new AppSettings();
        s.SetStyle(AppCategory.Chat, StylePreset.Casual);
        Assert.Equal(StylePreset.Casual, s.CategoryStyles["chat"]);
        Assert.Equal(StylePreset.Casual, s.StyleFor(AppCategory.Chat));
        s.SetStyle(AppCategory.Chat, StylePreset.Auto);
        Assert.Equal(StylePreset.Auto, s.StyleFor(AppCategory.Chat));
    }
}
