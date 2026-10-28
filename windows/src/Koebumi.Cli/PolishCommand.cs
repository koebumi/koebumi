using System.Diagnostics;
using System.Globalization;
using Koebumi.Core;

namespace Koebumi.Cli;

/// 音声ファイルやテキストで認識と整形を試す。Mac 版の CLI.run に当たる。
///   koebumi --transcribe sample.wav --mode translate --target en-US --category email
///   koebumi --polish "えーと、明日は3時、いや4時です" --vocab "Claude Code=クロードコード,Koebumi" --json
static class PolishCommand
{
    public static async Task<int> RunAsync(Options o, CliContext ctx)
    {
        var settings = ctx.Settings;
        var mode = o.Choice<Mode>("--mode", out var modeError) ?? Mode.Dictate;
        var category = o.Choice<AppCategory>("--category", out var categoryError) ?? AppCategory.Other;
        if ((modeError ?? categoryError) is { } problem) return Program.UsageError(problem);

        var path = o.Value("--transcribe");
        var text = o.Value("--polish");
        var lang = o.Value("--lang") ?? settings.CurrentDictationLanguage;
        var appName = o.Value("--app") ?? "Terminal";
        var json = o.Has("--json");
        Polisher.Verbose = o.Has("--verbose");
        if (Polisher.Verbose) ctx.DescribeKeys(transcribe: path != null);

        var vocabulary = ctx.Dictionary.Terms;
        var aliases = ctx.Dictionary.Aliases;
        var aliasHints = ctx.Dictionary.AliasHints;
        if (o.Value("--vocab") is { } spec) (vocabulary, aliases, aliasHints) = ParseVocabulary(spec);

        var fields = new Fields();
        try
        {
            string raw;
            if (path != null)
            {
                var audio = AudioLoader.Load(path);
                // 話す言語を --lang で指定したときは、それだけを認識に渡す（クラウドの認識が言語を決め打ちできる）。指定がなければアプリと同じく、設定の言語すべて
                var request = new TranscriptionRequest
                {
                    Languages = o.Value("--lang") is { } only ? [only] : settings.DictationLanguages,
                    Vocabulary = vocabulary,
                };
                var clock = Stopwatch.StartNew();
                raw = await ctx.MakeTranscriber().TranscribeAsync(audio, request);
                fields["raw_sec"] = JsonOutput.Seconds(clock.Elapsed);
                fields["raw_engine"] = Storage.Raw(settings.SttProvider);
            }
            else
            {
                raw = text ?? "";
            }
            fields["raw"] = raw;

            var engine = ctx.MakeEngine();
            var started = Stopwatch.StartNew();
            if (mode == Mode.Ask)
            {
                if (engine is null) throw LLMException.Unavailable(T("Ask anything には AI エンジンが必要です", "Ask anything needs an AI engine"));
                var selection = o.Value("--selection");
                var ask = new AskRequest
                {
                    Query = Polisher.Prepare(raw, aliases),
                    Selection = selection,
                    SelectionEditable = selection != null,
                    HasFocusedTextField = false,
                    AppName = appName,
                    Category = category,
                    Vocabulary = vocabulary,
                };
                var outcome = await engine.AskAsync(ask);
                fields["ask"] = Describe(outcome);
                fields["ask_sec"] = JsonOutput.Seconds(started.Elapsed);
                fields["ask_engine"] = engine.Name;
            }
            else
            {
                var polish = new PolishRequest
                {
                    Transcript = raw,
                    Mode = mode,
                    SourceLanguages = [lang],
                    TargetLanguage = mode == Mode.Translate ? o.Value("--target") ?? settings.CurrentTranslationTarget : null,
                    AppName = appName,
                    Category = category,
                    // Mac 版の CLI と同じく、アプリの種類の既定のトーン（設定の「スタイル」は使わない）
                    StyleDescription = category.DefaultStyleDescription,
                    PersonalStyle = settings.PersonalizationEnabled ? ctx.Personalization.Profile.PromptDescription(category) : null,
                    Vocabulary = vocabulary,
                    Corrections = settings.PersonalizationEnabled ? ctx.Personalization.Corrections : [],
                    Aliases = aliases,
                    AliasHints = aliasHints,
                    Notation = settings.JapaneseNotation,
                    ChatPunctuation = settings.ChatPunctuation,
                };
                var output = await Polisher.Run(polish, engine);
                fields["out"] = output.Text;
                fields["out_sec"] = JsonOutput.Seconds(started.Elapsed);
                fields["out_engine"] = engine?.Name ?? "basic";
                if (output.Warning is { } warning) fields["warning"] = warning;
            }
            Report(fields, json);
            return 0;
        }
        catch (Exception e)
        {
            fields["error"] = Program.Message(e);
            if (json) Report(fields, json);
            else Console.Out.WriteLine($"ERROR: {Program.Message(e)}");
            return 1;
        }
    }

    static void Report(Fields fields, bool json)
    {
        if (json)
        {
            Console.Out.WriteLine(JsonOutput.Compact(fields));
            return;
        }
        foreach (var key in new[] { "raw", "out", "ask" })
        {
            if (!fields.TryGetValue(key, out var value)) continue;
            var seconds = fields.GetValueOrDefault(key + "_sec") is double d ? d : 0;
            var engine = fields.GetValueOrDefault(key + "_engine") as string ?? "";
            Console.Out.WriteLine(string.Create(CultureInfo.InvariantCulture, $"{key.ToUpperInvariant()}  ({seconds:F2}s, {engine}): {value}"));
        }
        if (fields.TryGetValue("warning", out var warningText)) Console.Out.WriteLine($"WARNING: {warningText}");
    }

    /// Mac 版が Swift の列挙を文字にしたもの（answer("…")）に合わせる
    static string Describe(AskOutcome outcome) => outcome switch
    {
        AskOutcome.Answer a => $"answer(\"{a.Text}\")",
        AskOutcome.Replace r => $"replace(\"{r.Text}\")",
        AskOutcome.Insert i => $"insert(\"{i.Text}\")",
        AskOutcome.OpenURL u => $"openURL({u.Url}, \"{u.Description}\")",
        _ => outcome.ToString() ?? "",
    };

    /// "Claude Code=クロードコード|クロード・コード,田中~棚香,Koebumi" → 単語の一覧、置き換える聞き取られ方、AI へのヒントにする聞き取られ方。
    /// "=" は認識結果をそのまま置き換え、"~" は自動追加した漢字の語と同じく AI に文脈を見て直してもらう
    public static (List<string> Terms, Dictionary<string, string> Aliases, Dictionary<string, string> Hints) ParseVocabulary(string spec)
    {
        var terms = new List<string>();
        var aliases = new Dictionary<string, string>();
        var hints = new Dictionary<string, string>();
        foreach (var item in spec.Split(',', StringSplitOptions.RemoveEmptyEntries))
        {
            var hint = item.Contains('~');
            var separator = item.IndexOfAny(['=', '~']);
            var term = (separator < 0 ? item : item[..separator]).Trim();
            if (term.Length == 0) continue;
            terms.Add(term);
            if (separator < 0) continue;
            foreach (var heard in item[(separator + 1)..].Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                if (hint) hints[heard] = term;
                else aliases[heard] = term;
            }
        }
        return (terms, aliases, hints);
    }
}
