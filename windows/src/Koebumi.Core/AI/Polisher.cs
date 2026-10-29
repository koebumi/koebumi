using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace Koebumi.Core;

/// 認識結果から入力するテキストを作る。アプリと CLI（--polish）で同じ処理を通す。
/// 表記の統一と辞書の置き換え → AI 整形 → 出力の検証 → 表記の統一 → 日本語の表記ルール・チャットの句読点・画面の文脈に合わせる、の順に行う。
public static class Polisher
{
    /// CLI の --verbose: 使わなかった AI の出力を標準エラーに書く（開発用）
    public static bool Verbose { get; set; }

    public sealed record Output(
        string Text,
        // AI 整形を諦めて簡易整形にしたときの理由（ユーザーに知らせる）
        string? Warning = null,
        // AI を通さずに整えた文（フィラーの除去と表記の統一だけ）。入力した後に AI の整形を元に戻すときに使う
        string Plain = "");

    /// AI に渡す前の決まった下処理（Ask の質問にも使う）
    public static string Prepare(string transcript, IReadOnlyDictionary<string, string> aliases) =>
        VocabularyReplacer.Apply(TextNormalizer.Normalize(SpokenCommands.Apply(transcript)), aliases);

    /// 名前の読みには ScreenNameFixer.Reader を使う
    public static Task<Output> Run(PolishRequest request, ILLMEngine? engine, CancellationToken cancellationToken = default) =>
        Run(request, engine, ScreenNameFixer.Reader, cancellationToken);

    /// reader: 名前の読みを求める実装（テストでは偽の実装を渡す）
    public static async Task<Output> Run(PolishRequest request, ILLMEngine? engine, IJapaneseReader? reader, CancellationToken cancellationToken = default)
    {
        request = request with { Transcript = Prepare(request.Transcript, request.Aliases) };
        var cleaned = BasicCleaner.Clean(request.Transcript);
        // フィラーしか話していない（「えーと、あのー」）なら、AI に渡しても何も残らない
        if (cleaned.Length == 0) return new Output("");
        var fallback = Fit(cleaned, request, reader);
        if (engine is null)
        {
            if (request.Mode == Mode.Translate)
            {
                throw LLMException.Unavailable(T("翻訳には AI エンジンが必要です（設定 > 整形（AI））", "Translation needs an AI engine (Settings > Polish (AI))"));
            }
            return new Output(fallback, Plain: fallback);
        }
        try
        {
            if (request.Mode == Mode.Translate)
            {
                // フィラーは訳すと「Um,」などとして残るので、訳す前に取り除く
                request = request with { Transcript = cleaned };
                // 小さいモデルは訳さずに元の言語のまま返すことがあるので、翻訳先の文字で書かれているか確かめて 1 回だけやり直す
                var target = request.TargetLanguage ?? "en-US";
                for (int attempt = 0; attempt < 2; attempt++)
                {
                    var text = Finish(await engine.PolishAsync(request, cancellationToken), request);
                    if (text.Length > 0 && Languages.IsWritten(text, target)) return new Output(Fit(text, request, reader), Plain: fallback);
                    Debug.WriteLine($"Koebumi: translation is not in {target} (attempt {attempt + 1})");
                    if (Verbose) Console.Error.WriteLine($"rejected: {text}");
                }
                throw LLMException.Unavailable(T($"{Languages.Name(target)} に翻訳できませんでした。もう一度試すか、設定で別の AI エンジンを選んでください",
                                                 $"Could not translate into {Languages.Name(target)}. Try again or choose another AI engine in Settings"));
            }
            // 小さいモデルは同じ入力でもまれに崩れるので、不自然な出力なら 1 回だけやり直す
            // メールと、フォーマルな口調を選んだときは、です・ます調にしてよい
            var mayBePolite = request.Category == AppCategory.Email
                || request.StyleDescription.Contains("敬語", StringComparison.Ordinal)
                || request.StyleDescription.Contains("keigo", StringComparison.Ordinal);
            for (int attempt = 0; attempt < 2; attempt++)
            {
                var text = Finish(await engine.PolishAsync(request, cancellationToken), request);
                if (!mayBePolite) text = OutputGuard.KeepingCasualQuestions(request.Transcript, text);
                if (OutputGuard.Accepts(request.Transcript, text, request.Vocabulary, request.AllowsRewording)
                    && OutputGuard.KeepsCorrection(request.Transcript, text)
                    && OutputGuard.KeepsQuantityParticles(request.Transcript, text)
                    && OutputGuard.KeepsNames(request.Transcript, text, request.Vocabulary, reader)
                    && (mayBePolite || OutputGuard.KeepsRegister(request.Transcript, text)))
                {
                    return new Output(Fit(text, request, reader), Plain: fallback);
                }
                // 質問に答えた・内容を落とした・言い直しを取り違えたなど、整形として不自然な出力は使わない
                Debug.WriteLine($"Koebumi: rejected AI output (attempt {attempt + 1}). source={ContextText.Count(request.Transcript)} output={ContextText.Count(text)}");
                if (Verbose) Console.Error.WriteLine($"rejected: {text}");
            }
            return new Output(fallback, Plain: fallback);
        }
        catch (Exception e)
        {
            // 取り消し。HttpClient のタイムアウトも OperationCanceledException だが、それは取り消しではなく失敗として扱う
            if (cancellationToken.IsCancellationRequested) throw new OperationCanceledException(cancellationToken);
            if (request.Mode == Mode.Translate) throw;
            // 整形に失敗しても話した内容は失わない
            var warning = T("AI 整形に失敗したため認識結果を入力しました: ", "AI cleanup failed, inserted the transcript: ") + e.Message;
            return new Output(fallback, warning, fallback);
        }
    }

    /// AI の出力の表記をそろえ、辞書の表記に直す
    static string Finish(string polished, PolishRequest request)
    {
        var text = request.Mode == Mode.Dictate ? BasicCleaner.RemoveFillers(polished) : polished;
        return VocabularyReplacer.Apply(ListTidier.Tidy(TextNormalizer.Normalize(text)), request.Aliases);
    }

    /// 入力する直前に、日本語の表記ルール、チャットの句読点、画面に合わせた人名の表記、メールの宛名と挨拶、カーソル前後とのつなぎ方をそろえる。
    /// 名前の読みには ScreenNameFixer.Reader を使う
    public static string Fit(string text, PolishRequest request) => Fit(text, request, ScreenNameFixer.Reader);

    public static string Fit(string text, PolishRequest request, IJapaneseReader? reader)
    {
        var t = text;
        // 文頭で大文字にされた名前（build-app → Build-app、iPhone → IPhone）を、辞書や作業フォルダの表記に戻す
        foreach (var term in request.Vocabulary)
        {
            var first = ContextText.First(term);
            if (!ContextText.IsLowercase(first)) continue;
            var capitalized = Regex.Escape(first.ToUpperInvariant() + term[first.Length..]);
            t = Regex.Replace(t, "(?<![A-Za-z0-9])" + capitalized + "(?![A-Za-z0-9])", _ => term, RegexOptions.CultureInvariant);
        }
        if (request.Notation is { } n) t = JapaneseFormatter.Apply(t, n);
        if (request.Category == AppCategory.Chat)
        {
            var rule = request.Mode == Mode.Translate ? request.ChatPunctuation.ForTranslation : request.ChatPunctuation;
            t = rule.Apply(t);
        }
        if (request.Surrounding is { } s)
        {
            t = ScreenNameFixer.Apply(t, string.Join("\n", s.Screen, s.Before, s.After, s.ScreenAfter), reader);
        }
        // 名前の表記を画面に合わせてから、敬称を返信先に合わせる（しょうじさん → 東海林さん → 東海林様）
        if (request.MailReply is { } reply) t = MailReply.Adjust(t, reply);
        if (request.Surrounding is { } s2)
        {
            t = ContextJoiner.Join(t, s2.Before, s2.After);
        }
        return t;
    }
}

/// AI の整形結果が「話した内容をきれいにしたもの」になっているかを確かめる。
/// 小さいモデルは書き起こしの質問に答えたり、断ったり、大きく省いたりすることがあるため。
public static class OutputGuard
{
    static readonly string[] RefusalMarkers =
    [
        "申し訳ありません", "申し訳ございません", "お手伝いできません", "対応できません", "AIとして", "AI として", "言語モデル",
        "I'm sorry", "I am sorry", "I can't help", "I cannot help", "I can't assist", "I cannot assist", "As an AI", "language model",
    ];

    /// allowsRewording: 言葉づかいを指定して言い換えさせるとき（敬語化など）は、文字の重なりが少なくても受け入れる
    public static bool Accepts(string source, string output, IReadOnlyList<string>? vocabulary = null, bool allowsRewording = false)
    {
        var s = Letters(source);
        // 辞書の語（カタカナを英語表記に直したものなど）は、話した内容と文字が重ならなくても正しい
        var stripped = output;
        foreach (var term in (vocabulary ?? []).OrderByDescending(ContextText.Count))
        {
            if (term.Length == 0) continue;
            stripped = stripped.Replace(term, " ", StringComparison.OrdinalIgnoreCase);
        }
        var o = Letters(stripped);
        if (Letters(output).Count == 0) return s.Count == 0;
        if (s.Count == 0) return false;
        // 話していない内容を大量に足した（質問に答えた・続きを書いた）
        if (o.Count > s.Count * 3 / 2 + 20) return false;
        // 大部分を落とした（フィラーと言い直しを除いても 3 割未満）
        var cleaned = Letters(BasicCleaner.Clean(source));
        if (cleaned.Count >= 20 && o.Count * 10 < cleaned.Count * 3) return false;
        // 出力の大部分が、話した内容に出てこない文字の並びでできている（短い出力ほど厳しく見る）
        if (o.Count >= 4 && Overlap(o, s) < (allowsRewording ? 0.12 : o.Count < 12 ? 0.5 : 0.3)) return false;
        foreach (var marker in RefusalMarkers)
        {
            if (output.Contains(marker, StringComparison.OrdinalIgnoreCase) && !source.Contains(marker, StringComparison.OrdinalIgnoreCase)) return false;
        }
        return true;
    }

    /// 言い直しがあるとき、言い直した後の語が出力に残っているか（「9時、違う、9時半」なら「9時半」）
    public static bool KeepsCorrection(string source, string output)
    {
        if (Prompts.FindCorrection(source) is not { } c) return true;
        var head = Letters(c.After).Take(3).ToList();
        if (head.Count < 2) return true;
        return string.Concat(Letters(output)).Contains(string.Concat(head), StringComparison.Ordinal);
    }

    static readonly Regex QuantityParticle = new(
        @"([0-9]+(?:時半|時|分|日|月|年|円|万円|人|名|個|件|回|ドル|%))(までに|から|まで|より|に)?", RegexOptions.CultureInvariant);

    /// 時刻・金額などの後の「に」「から」「まで」を AI が変えたり、足したり、落としたりしていないか
    /// （「3時に 4時からの会議」→「3時から4時からの会議」や「3時、4時からの会議」は意味が変わる）。
    /// 言い直しで消えた数（「3時、いや4時」の「3時」）は比べない。
    public static bool KeepsQuantityParticles(string source, string output)
    {
        static Dictionary<string, HashSet<string>> Particles(string text)
        {
            var map = new Dictionary<string, HashSet<string>>();
            foreach (Match m in QuantityParticle.Matches(text))
            {
                var quantity = m.Groups[1].Value;
                var particle = m.Groups[2].Value;
                if (!map.TryGetValue(quantity, out var set)) map[quantity] = set = [];
                // 「3時より」は「3時から」の改まった言い方（ビジネス敬語で言い換える）なので同じとみなす
                set.Add(particle == "より" ? "から" : particle);
            }
            return map;
        }
        var original = Particles(source);
        foreach (var (quantity, used) in Particles(output))
        {
            if (!original.TryGetValue(quantity, out var said)) continue;
            if (used.Any(p => !said.Contains(p))) return false;
        }
        return true;
    }

    /// 敬称の付いた名前を、話していない名前に変えていないか。画面の人名を AI に渡すと、小さいモデルは
    /// 別の人の名前（返信先のメールの宛名に出ている自分の名前など）に書き換えることがある（しょうじさん → 矢野さん）。
    /// 話した中に同じ字か同じ読みがある名前と、辞書の語は正しい（しょうじさん → 東海林さん）。
    /// 名前の読みには ScreenNameFixer.Reader を使う
    public static bool KeepsNames(string source, string output, IReadOnlyList<string>? vocabulary = null) =>
        KeepsNames(source, output, vocabulary, ScreenNameFixer.Reader);

    public static bool KeepsNames(string source, string output, IReadOnlyList<string>? vocabulary, IJapaneseReader? reader)
    {
        vocabulary ??= [];
        var tokens = ScreenNameFixer.Tokens(output, reader);
        var heard = LooseReading(string.Concat(ScreenNameFixer.Tokens(source, reader).Select(t => t.Reading.Length == 0 ? t.Surface : t.Reading)));
        for (int i = 0; i + 1 < tokens.Count; i++)
        {
            if (!ScreenNameFixer.Honorifics.Contains(tokens[i + 1].Surface)) continue;
            var name = tokens[i];
            if (!name.Surface.All(c => CharClasses.Of(c) == CharClass.Han)
                || source.Contains(name.Surface, StringComparison.Ordinal)
                || vocabulary.Contains(name.Surface))
                continue;
            var reading = LooseReading(name.Reading);
            if (reading.Length == 0 || !heard.Contains(reading, StringComparison.Ordinal)) return false;
        }
        return true;
    }

    /// 長音の書き方の違い（shouji・shōji・shoji）を除いた読み
    static string LooseReading(string reading)
    {
        var folded = new StringBuilder();
        foreach (var c in reading.ToLowerInvariant().Normalize(NormalizationForm.FormD))
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) folded.Append(c);
        }
        var k = new StringBuilder();
        foreach (var rune in folded.ToString().Normalize(NormalizationForm.FormC).EnumerateRunes())
        {
            if (Rune.IsLetter(rune)) k.Append(rune.ToString());
        }
        var result = k.ToString();
        foreach (var (longVowel, shortVowel) in new[] { ("ou", "o"), ("oo", "o"), ("uu", "u"), ("aa", "a"), ("ii", "i"), ("ee", "e") })
        {
            result = result.Replace(longVowel, shortVowel, StringComparison.Ordinal);
        }
        return result;
    }

    /// 丁寧語の目印。話した中にこれがなければ、くだけた口調で話している。
    static readonly string[] PoliteMarkers = ["です", "ます", "ました", "ません", "ましょう", "ください", "下さい", "でしょう", "ございます"];

    static bool IsPolite(string text) => PoliteMarkers.Any(m => text.Contains(m, StringComparison.Ordinal));

    static readonly Regex PoliteQuestion = new(@"(?:ですか|でしょうか)[？?。]", RegexOptions.CultureInvariant);

    /// です・ます調で話していないのに AI が足した「ですか」を外す（「今何時ですか？」→「今何時？」）
    public static string KeepingCasualQuestions(string source, string output) =>
        IsPolite(source) ? output : PoliteQuestion.Replace(output, "？");

    /// くだけた口調で話したのに、AI が です・ます調に書き換えていないか（「間違ってた」→「間違っていました」）
    public static bool KeepsRegister(string source, string output) => IsPolite(source) || !IsPolite(output);

    /// 文字と数字だけを小文字で取り出す（空白・句読点・記号を除く）。1 文字は書記素クラスター（Swift の Character）
    public static IReadOnlyList<string> Letters(string text) =>
        [.. ContextText.Elements(text.ToLowerInvariant()).Where(ContextText.IsLetterOrNumber)];

    /// a の 2 文字の並びのうち、b にも出てくるものの割合
    public static double Overlap(IReadOnlyList<string> a, IReadOnlyList<string> b)
    {
        if (a.Count < 2 || b.Count < 2) return a.SequenceEqual(b) ? 1 : 0;
        var pairs = new HashSet<string>();
        for (int i = 0; i + 1 < b.Count; i++) pairs.Add(b[i] + b[i + 1]);
        int hits = 0;
        for (int i = 0; i + 1 < a.Count; i++)
        {
            if (pairs.Contains(a[i] + a[i + 1])) hits++;
        }
        return (double)hits / (a.Count - 1);
    }
}
