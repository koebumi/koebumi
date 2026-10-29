using System.Globalization;

namespace Koebumi.Core;

/// 2 つの文の違い。履歴で、AI の整形が変えたところ（消した語と足した語）を見せるのに使う
public static class TextDiff
{
    public enum Kind { Same, Removed, Added }

    public readonly record struct Segment(Kind Kind, string Text);

    /// old から new への違いを、同じ部分・消した部分・足した部分の並びにする。
    /// 言い換えで 1 文字だけ同じ字が残った箇所（「見ました」→「拝見しました」の「見」）は、前後の変更とまとめて読みやすくする
    public static List<Segment> Segments(string from, string to)
    {
        // Swift の Character と同じく、結合文字や絵文字を 1 文字として比べる
        var a = Graphemes(from);
        var b = Graphemes(to);
        var chunks = new List<(string? Same, string Removed, string Added)>();
        int i = 0;
        foreach (var (o, n) in Changes(a, b))
        {
            if (i < o.Lower) chunks.Add((Join(a, i, o.Lower), "", ""));
            chunks.Add((null, Join(a, o.Lower, o.Upper), Join(b, n.Lower, n.Upper)));
            i = o.Upper;
        }
        if (i < a.Length) chunks.Add((Join(a, i, a.Length), "", ""));

        var merged = new List<(string? Same, string Removed, string Added)>();
        int k = 0;
        while (k < chunks.Count)
        {
            var c = chunks[k];
            if (c.Same is { } same && new StringInfo(same).LengthInTextElements <= 1 && merged.Count > 0 && merged[^1].Same == null
                && k + 1 < chunks.Count && chunks[k + 1].Same == null)
            {
                var last = merged[^1];
                var next = chunks[k + 1];
                merged[^1] = (null, last.Removed + same + next.Removed, last.Added + same + next.Added);
                k += 2;
                continue;
            }
            if (c.Same == null && merged.Count > 0 && merged[^1].Same == null)
            {
                var last = merged[^1];
                merged[^1] = (null, last.Removed + c.Removed, last.Added + c.Added);
            }
            else
            {
                merged.Add(c);
            }
            k++;
        }

        var result = new List<Segment>();
        foreach (var c in merged)
        {
            if (c.Same is { } same)
            {
                result.Add(new Segment(Kind.Same, same));
                continue;
            }
            if (c.Removed.Length > 0) result.Add(new Segment(Kind.Removed, c.Removed));
            if (c.Added.Length > 0) result.Add(new Segment(Kind.Added, c.Added));
        }
        return result;
    }

    static string[] Graphemes(string text)
    {
        var result = new List<string>();
        var e = StringInfo.GetTextElementEnumerator(text);
        while (e.MoveNext()) result.Add(e.GetTextElement());
        return [.. result];
    }

    static string Join(string[] chars, int start, int end) => string.Concat(chars[start..end]);

    // 以下は Mac 版の CorrectionDetector.changes（System/CorrectionWatcher.swift）と同じ処理。
    // Mac 版の TextDiff はそれを呼ぶが、CorrectionDetector は別の部分なので、ここに同じものを置く

    readonly record struct IntRange(int Lower, int Upper)
    {
        public int Count => Upper - Lower;
        public bool IsEmpty => Lower == Upper;
    }

    /// 入力欄全体の変わった箇所の位置。端末の画面全体（1 万字ほど）を毎秒比べても重くならないよう、前後の同じ部分を除き、
    /// まだ長ければ行ごとに比べてから、変わった行の中を文字ごとに比べる。それでも長く変わった部分は、まとめて 1 か所の書き換えとする。
    static List<(IntRange Old, IntRange New)> Changes(string[] a, string[] b)
    {
        int p = 0;
        while (p < a.Length && p < b.Length && a[p] == b[p]) p++;
        int ea = a.Length, eb = b.Length;
        while (ea > p && eb > p && a[ea - 1] == b[eb - 1])
        {
            ea--;
            eb--;
        }
        if (!(p < ea || p < eb)) return [];
        var midA = a[p..ea];
        var midB = b[p..eb];
        static (IntRange, IntRange) Shift((IntRange Old, IntRange New) span, int da, int db) =>
            (new(span.Old.Lower + da, span.Old.Upper + da), new(span.New.Lower + db, span.New.Upper + db));
        if (midA.Length + midB.Length <= CharDiffLimit)
        {
            return Spans(midA, midB).Select(s => Shift(s, p, p)).ToList();
        }
        var linesA = Lines(midA);
        var linesB = Lines(midB);
        var result = new List<(IntRange Old, IntRange New)>();
        foreach (var block in Spans(linesA.Select(l => l.Text).ToArray(), linesB.Select(l => l.Text).ToArray()))
        {
            // 端末の画面のように、同じ数の行が書き換わったときは行どうしを比べる（左右に並べた画面は、どの行にも別の画面の文字が入る）
            var pairs = block.Old.Count == block.New.Count
                ? Enumerable.Range(0, block.Old.Count).Select(x => (linesA[block.Old.Lower + x].Range, linesB[block.New.Lower + x].Range)).ToList()
                : [(CharRange(block.Old, linesA, midA.Length), CharRange(block.New, linesB, midB.Length))];
            foreach (var (old, @new) in pairs)
            {
                if (old.Count + @new.Count > CharDiffLimit)
                {
                    result.Add(Shift((old, @new), p, p));
                    continue;
                }
                result.AddRange(Spans(midA[old.Lower..old.Upper], midB[@new.Lower..@new.Upper]).Select(s => Shift(s, p + old.Lower, p + @new.Lower)));
            }
        }
        return result;
    }

    const int CharDiffLimit = 3000;

    /// 改行で区切った行（改行を含む）
    static List<(IntRange Range, string Text)> Lines(string[] chars)
    {
        var result = new List<(IntRange Range, string Text)>();
        int start = 0;
        for (int i = 0; i < chars.Length; i++)
        {
            if (chars[i] != "\n" && i != chars.Length - 1) continue;
            result.Add((new IntRange(start, i + 1), Join(chars, start, i + 1)));
            start = i + 1;
        }
        return result;
    }

    /// 何行目から何行目までを、文字の位置の範囲にする（行がない位置なら、その前の行の終わり）
    static IntRange CharRange(IntRange lineRange, List<(IntRange Range, string Text)> lines, int total)
    {
        int start = lineRange.Lower < lines.Count ? lines[lineRange.Lower].Range.Lower : total;
        int end = lineRange.IsEmpty ? start : lines[lineRange.Upper - 1].Range.Upper;
        return new IntRange(start, end);
    }

    /// 変わった箇所の位置（変更前・変更後）。Myers の差分で取り、まとめない
    static List<(IntRange Old, IntRange New)> Spans(string[] a, string[] b)
    {
        var (removed, inserted) = Difference(a, b);
        var result = new List<(IntRange Old, IntRange New)>();
        int i = 0, j = 0;
        while (i < a.Length || j < b.Length)
        {
            if (!removed.Contains(i) && !inserted.Contains(j))
            {
                i++;
                j++;
                continue;
            }
            int si = i, sj = j;
            while (removed.Contains(i) || inserted.Contains(j))
            {
                if (removed.Contains(i)) i++;
                else j++;
            }
            result.Add((new IntRange(si, i), new IntRange(sj, j)));
        }
        return result;
    }

    /// Swift の b.difference(from: a)（標準ライブラリの Myers の差分）と同じ手順で、消した位置（a の中）と足した位置（b の中）を求める。
    /// 同じ長さの差分がいくつもあるときに、Mac 版と同じものを選ぶため、手順もそろえる
    static (HashSet<int> Removed, HashSet<int> Inserted) Difference(string[] a, string[] b)
    {
        int n = a.Length, m = b.Length;
        // 斜めの線 k（-d から d まで 2 つおき）ごとの到達点 x。負の k は正の k の間に詰めて持つ
        static int Index(int k) => k <= 0 ? -k : k - 1;

        var trace = new List<int[]>();
        var v = new int[2];
        v[Index(1)] = 0;
        int x = 0, y = 0;
        for (int d = 0; d <= n + m; d++)
        {
            var prev = v;
            trace.Add(v);
            v = new int[d + 1];
            for (int k = -d; k <= d; k += 2)
            {
                if (k == -d)
                {
                    x = prev[Index(k + 1)];
                }
                else
                {
                    int km = prev[Index(k - 1)];
                    if (k != d)
                    {
                        int kp = prev[Index(k + 1)];
                        x = km < kp ? kp : km + 1;
                    }
                    else
                    {
                        x = km + 1;
                    }
                }
                y = x - k;
                while (x < n && y < m && a[x] == b[y])
                {
                    x++;
                    y++;
                }
                v[Index(k)] = x;
                if (x >= n && y >= m) break;
            }
            if (x >= n && y >= m) break;
        }

        var removed = new HashSet<int>();
        var inserted = new HashSet<int>();
        x = n;
        y = m;
        for (int d = trace.Count - 1; d > 0; d--)
        {
            var row = trace[d];
            int k = x - y;
            int prevK = k == -d || (k != d && row[Index(k - 1)] < row[Index(k + 1)]) ? k + 1 : k - 1;
            int prevX = row[Index(prevK)];
            int prevY = prevX - prevK;
            while (x > prevX && y > prevY)
            {
                x--;
                y--;
            }
            if (y != prevY) inserted.Add(prevY);
            else removed.Add(prevX);
            x = prevX;
            y = prevY;
        }
        return (removed, inserted);
    }
}
