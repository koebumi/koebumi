using System.Runtime.ExceptionServices;
using Koebumi.Core;
using Windows.Globalization;

namespace Koebumi.App;

/// Windows.Globalization.JapanesePhoneticAnalyzer で、文を語に分けて読みを付ける。Mac 版の CFStringTokenizer に当たる。
/// どのスレッドからでも呼べる（このクラスは STA の作業スレッドで解析する。下の OnStaThread）
public sealed class JapanesePhoneticReader : IJapaneseReader
{
    // GetWords は、入力が 100 文字を超えると、エラーも出さずに空の結果を返す（実機で 100 文字までと 101 文字で確かめた）。
    // 長い文は、句点・読点・空白・改行の後ろで、80 文字以内に分けて解析する
    const int ChunkLength = 80;
    const int ChunkSlack = 30;

    /// 直近の Tokenize が失敗した理由（成功したら null）。日本語の辞書を使えない PC の見分けに使う
    public Exception? LastError { get; private set; }

    public IReadOnlyList<ReadingToken> Tokenize(string text)
    {
        LastError = null;
        try
        {
            return OnStaThread(() =>
            {
                var tokens = new List<ReadingToken>();
                int offset = 0;
                while (offset < text.Length)
                {
                    int length = ChunkEnd(text, offset) - offset;
                    Analyze(text, offset, length, tokens);
                    offset += length;
                }
                return tokens;
            });
        }
        catch (Exception e)
        {
            // 日本語の辞書を使えないときは、読みなしとして扱う（呼び出し側は読みのない語を数えない）
            LastError = e;
            return [];
        }
    }

    static void Analyze(string text, int offset, int length, List<ReadingToken> tokens)
    {
        var chunk = text.Substring(offset, length);
        int position = 0;
        foreach (var word in JapanesePhoneticAnalyzer.GetWords(chunk))
        {
            var surface = word.DisplayText;
            if (surface.Length == 0) continue;
            // 解析結果の表記をつなげると元の文になる。ただし半角の空白は全角になって返るので、
            // 見つからないときは、直前の続きの同じ長さを、元の文の表記として使う
            int start = chunk.IndexOf(surface, position, StringComparison.Ordinal);
            if (start < 0)
            {
                start = position;
                surface = chunk.Substring(start, Math.Min(surface.Length, chunk.Length - start));
                if (surface.Length == 0) continue;
            }
            position = Math.Min(start + surface.Length, chunk.Length);
            // 読めなかった漢字は表記がそのまま返るので、読みなしにする
            var reading = word.YomiText.Any(IsHan) ? "" : word.YomiText;
            tokens.Add(new ReadingToken(surface, reading, offset + start));
        }
    }

    /// offset から始まる 1 つのまとまりの終わり。上限の手前の ChunkSlack 文字のなかで、最後の区切りの後ろ（なければ上限）
    static int ChunkEnd(string text, int offset)
    {
        int limit = offset + ChunkLength;
        if (limit >= text.Length) return text.Length;
        for (int i = limit; i > limit - ChunkSlack; i--)
        {
            if (text[i - 1] is '。' or '！' or '？' or '\n' or ' ' or '、') return i;
        }
        // 区切りがなければ、サロゲートペアを割らずにその場で切る
        return char.IsHighSurrogate(text[limit - 1]) ? limit - 1 : limit;
    }

    static bool IsHan(char c) => (int)c is >= 0x4E00 and <= 0x9FFF or >= 0x3400 and <= 0x4DBF or >= 0xF900 and <= 0xFAFF;

    // MARK: - STA の作業スレッド

    // JapanesePhoneticAnalyzer は STA のクラス（レジストリの Threading=1）で、MTA のスレッド（スレッド プールなど）から
    // 呼ぶと 0x80040111（ClassFactory は要求されたクラスを提供できません）で失敗する。解析は専用の STA スレッドで行う
    static readonly object workerGate = new();
    static readonly System.Collections.Concurrent.BlockingCollection<Action> work = [];
    static Thread? worker;

    static T OnStaThread<T>(Func<T> run)
    {
        if (Thread.CurrentThread.GetApartmentState() == ApartmentState.STA) return run();
        lock (workerGate)
        {
            if (worker == null)
            {
                worker = new Thread(() => { foreach (var item in work.GetConsumingEnumerable()) item(); })
                { IsBackground = true, Name = "japanese-phonetic" };
                worker.SetApartmentState(ApartmentState.STA);
                worker.Start();
            }
        }
        T result = default!;
        Exception? error = null;
        using var done = new ManualResetEventSlim();
        work.Add(() =>
        {
            try { result = run(); }
            catch (Exception e) { error = e; }
            finally { done.Set(); }
        });
        if (!done.Wait(TimeSpan.FromSeconds(5))) throw new TimeoutException("日本語の読みの解析が終わらない");
        if (error != null) ExceptionDispatchInfo.Capture(error).Throw();
        return result;
    }
}
