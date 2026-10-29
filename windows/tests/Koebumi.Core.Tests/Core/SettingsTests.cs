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
}
