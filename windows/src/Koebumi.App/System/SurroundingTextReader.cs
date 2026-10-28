using System.Diagnostics;
using Interop.UIAutomationClient;
using Koebumi.Core;

namespace Koebumi.App;

/// UI Automation（COM の IUIAutomation）で、フォーカスのある入力欄のカーソル前後と、同じ窓に表示されている文字列を読む。
/// Mac 版の SurroundingTextReader に当たる。UI のないスレッド（MTA）で動かす。
/// 自分のプロセスの窓を UI スレッドから読むと止まることがあるため、ReadAsync は Task.Run で読む
public static class SurroundingTextReader
{
    /// 全体で使える時間
    const int BudgetMs = 300;
    const int MaxNodes = 2500;

    /// 前面の窓の文脈を読む。パスワード欄・読めないアプリ・時間切れのときは null。
    /// 入力欄の外の文字列（Screen・ScreenAfter）は、窓の要素を 1 回の呼び出しでまとめて写して（BuildUpdatedCache）たどる
    public static async Task<SurroundingText?> ReadAsync()
    {
        var read = Task.Run(() => ReadDetailed().Text);
        // COM の呼び出しは取り消せない。間に合わなければ待たずに諦める（読み取りは裏で終わる）
        return await Task.WhenAny(read, Task.Delay(BudgetMs)) == read ? await read : null;
    }

    /// 読み取りの結果と、確かめるための情報
    internal sealed record Detail(SurroundingText? Text, string Info, int Nodes, double Ms);

    static readonly HashSet<int> SkippedTypes =
    [
        UIA_ControlTypeIds.UIA_MenuBarControlTypeId, UIA_ControlTypeIds.UIA_MenuControlTypeId, UIA_ControlTypeIds.UIA_MenuItemControlTypeId,
        UIA_ControlTypeIds.UIA_ButtonControlTypeId, UIA_ControlTypeIds.UIA_SplitButtonControlTypeId, UIA_ControlTypeIds.UIA_ScrollBarControlTypeId,
        UIA_ControlTypeIds.UIA_ToolBarControlTypeId, UIA_ControlTypeIds.UIA_RadioButtonControlTypeId, UIA_ControlTypeIds.UIA_CheckBoxControlTypeId,
        UIA_ControlTypeIds.UIA_ImageControlTypeId, UIA_ControlTypeIds.UIA_TitleBarControlTypeId,
    ];

    /// MTA のスレッドで呼ぶ
    internal static Detail ReadDetailed()
    {
        var clock = Stopwatch.StartNew();
        int nodes = 0;
        string info = "";
        try
        {
            var automation = UiAutomation.Instance;
            var focused = automation.GetFocusedElement();
            int retries = 0;
            // Chromium（Chrome・Edge・Electron・WebView2）は UI Automation のクライアントが来てからページの木を作る。
            // それまではフォーカスが外側の枠（Pane）になり、テキストのパターンがないので、30 ms 待って取り直す
            while (focused != null && retries < 8 && clock.ElapsedMilliseconds < BudgetMs * 2 / 3
                && focused.CurrentFrameworkId == "Chrome" && !HasTextPatterns(focused))
            {
                Thread.Sleep(30);
                retries++;
                focused = automation.GetFocusedElement();
            }
            if (focused == null) return new Detail(null, "フォーカスのある要素がない", 0, clock.Elapsed.TotalMilliseconds);
            // パスワード欄は読まない
            if (focused.CurrentIsPassword != 0) return new Detail(null, "パスワード欄", 0, clock.Elapsed.TotalMilliseconds);

            var (before, after, method) = CaretText(focused);
            info = retries > 0 ? $"{method}（取り直し {retries} 回）" : method;

            string screen = "", screenAfter = "";
            var hwnd = Native.GetForegroundWindow();
            if (hwnd != IntPtr.Zero && clock.ElapsedMilliseconds < BudgetMs)
            {
                var root = automation.ElementFromHandle(hwnd);
                if (root != null) (screen, screenAfter, nodes) = Window(automation, root, focused, clock);
            }

            var text = new SurroundingText
            {
                Before = TakeLast(before, SurroundingText.MaxBefore),
                After = TakeFirst(after, SurroundingText.MaxAfter),
                Screen = screen,
                ScreenAfter = screenAfter,
            };
            return new Detail(text, info, nodes, clock.Elapsed.TotalMilliseconds);
        }
        catch (Exception e)
        {
            return new Detail(null, e.GetType().Name + ": " + e.Message, nodes, clock.Elapsed.TotalMilliseconds);
        }
    }

    static bool HasTextPatterns(IUIAutomationElement e) =>
        e.GetCurrentPattern(UIA_PatternIds.UIA_TextPatternId) != null || e.GetCurrentPattern(UIA_PatternIds.UIA_ValuePatternId) != null;

    /// カーソル前後の文字列。TextPattern2 のカーソル位置か、TextPattern の選択範囲から、上限の長さまでだけ取り出す
    static (string Before, string After, string Method) CaretText(IUIAutomationElement el)
    {
        const TextPatternRangeEndpoint Start = TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start;
        const TextPatternRangeEndpoint End = TextPatternRangeEndpoint.TextPatternRangeEndpoint_End;
        IUIAutomationTextRange? caret = null;
        IUIAutomationTextPattern? pattern;
        string method;
        if (el.GetCurrentPattern(UIA_PatternIds.UIA_TextPattern2Id) is IUIAutomationTextPattern2 pattern2)
        {
            pattern = pattern2;
            caret = pattern2.GetCaretRange(out _);
            method = "TextPattern2.GetCaretRange";
            // 選択しているときは選択範囲を使う（カーソルは選択の片端にある）
            var selection = pattern2.GetSelection();
            if (selection != null && selection.Length > 0)
            {
                var range = selection.GetElement(0);
                if (range.GetText(1).Length > 0) { caret = range; method = "TextPattern2.GetSelection"; }
            }
        }
        else if (el.GetCurrentPattern(UIA_PatternIds.UIA_TextPatternId) is IUIAutomationTextPattern text)
        {
            pattern = text;
            var selection = text.GetSelection();
            if (selection != null && selection.Length > 0) caret = selection.GetElement(0);
            method = "TextPattern.GetSelection";
        }
        else if (el.GetCurrentPattern(UIA_PatternIds.UIA_ValuePatternId) is IUIAutomationValuePattern value)
        {
            // カーソル位置がわからないので、すべてをカーソルより前とみなす
            return (value.CurrentValue ?? "", "", "ValuePattern（カーソル位置なし）");
        }
        else return ("", "", "テキストのパターンなし");

        if (caret == null) return ("", "", method + "（範囲なし）");

        var before = caret.Clone();
        before.MoveEndpointByRange(End, caret, Start);
        before.MoveEndpointByUnit(Start, TextUnit.TextUnit_Character, -SurroundingText.MaxBefore);
        var after = caret.Clone();
        after.MoveEndpointByRange(Start, caret, End);
        after.MoveEndpointByUnit(End, TextUnit.TextUnit_Character, SurroundingText.MaxAfter);
        // Chromium では、文字単位で動かすと入力欄を越えてページの文字まで入る。入力欄（DocumentRange）の端で切る
        var field = pattern.DocumentRange;
        if (before.CompareEndpoints(Start, field, Start) < 0) before.MoveEndpointByRange(Start, field, Start);
        if (after.CompareEndpoints(End, field, End) > 0) after.MoveEndpointByRange(End, field, End);
        return (before.GetText(SurroundingText.MaxBefore * 2) ?? "", after.GetText(SurroundingText.MaxAfter * 2) ?? "", method);
    }

    /// 窓の要素を 1 回の呼び出しでまとめて写し（キャッシュ）、手元でたどる
    static (string Before, string After, int Nodes) Window(IUIAutomation automation, IUIAutomationElement root, IUIAutomationElement focused, Stopwatch clock)
    {
        var request = automation.CreateCacheRequest();
        request.AddProperty(UIA_PropertyIds.UIA_NamePropertyId);
        request.AddProperty(UIA_PropertyIds.UIA_ControlTypePropertyId);
        request.AddProperty(UIA_PropertyIds.UIA_IsPasswordPropertyId);
        request.AddProperty(UIA_PropertyIds.UIA_RuntimeIdPropertyId);
        request.AddProperty(UIA_PropertyIds.UIA_ValueValuePropertyId);
        request.TreeScope = TreeScope.TreeScope_Subtree;
        request.TreeFilter = automation.ControlViewCondition;
        // 写した要素から子を問い合わせることはないので、生きた要素にしない
        request.AutomationElementMode = AutomationElementMode.AutomationElementMode_None;

        var collector = new Collector(RuntimeId(focused, cached: false), clock);
        var tree = root.BuildUpdatedCache(request);
        void Visit(IUIAutomationElement e, int depth)
        {
            if (depth > 60 || collector.Nodes >= MaxNodes || clock.ElapsedMilliseconds > BudgetMs) return;
            if (!collector.Take(e)) return;
            var children = e.GetCachedChildren();
            if (children == null) return;
            for (int i = 0; i < children.Length; i++) Visit(children.GetElement(i), depth + 1);
        }
        Visit(tree, 0);
        return collector.Result();
    }

    static int[] RuntimeId(IUIAutomationElement e, bool cached)
    {
        try
        {
            object value = cached ? e.GetCachedPropertyValue(UIA_PropertyIds.UIA_RuntimeIdPropertyId) : e.GetRuntimeId();
            return value as int[] ?? [];
        }
        catch (Exception)
        {
            return [];
        }
    }

    /// 入力欄より前と後の、窓の文字列を集める
    sealed class Collector(int[] focusedId, Stopwatch clock)
    {
        readonly List<string> before = [], after = [];
        bool passed;
        public int Nodes { get; private set; }

        /// 子をたどるなら true
        public bool Take(IUIAutomationElement e)
        {
            Nodes++;
            if (!passed && focusedId.Length > 0 && RuntimeId(e, cached: true).SequenceEqual(focusedId))
            {
                // 入力欄そのものと、その中は読まない（ここから後ろは入力欄より後ろ）
                passed = true;
                return false;
            }
            int type = e.CachedControlType;
            if (SkippedTypes.Contains(type) || e.CachedIsPassword != 0) return false;
            string? text = null;
            if (type == UIA_ControlTypeIds.UIA_TextControlTypeId) text = e.CachedName;
            else if (type == UIA_ControlTypeIds.UIA_EditControlTypeId) text = e.GetCachedPropertyValue(UIA_PropertyIds.UIA_ValueValuePropertyId) as string;
            text = text?.Trim();
            var list = passed ? after : before;
            if (!string.IsNullOrEmpty(text) && (list.Count == 0 || list[^1] != text)) list.Add(text);
            return type != UIA_ControlTypeIds.UIA_EditControlTypeId && clock.ElapsedMilliseconds <= BudgetMs;
        }

        public (string Before, string After, int Nodes) Result() =>
            (TakeLast(string.Join("\n", before), SurroundingText.MaxScreen).Trim(), TakeFirst(string.Join("\n", after), SurroundingText.MaxScreenAfter).Trim(), Nodes);
    }

    /// 後ろから length 文字（サロゲートペアを割らない）
    static string TakeLast(string s, int length)
    {
        if (s.Length <= length) return s;
        var start = s.Length - length;
        if (char.IsLowSurrogate(s[start])) start++;
        return s[start..];
    }

    /// 前から length 文字（サロゲートペアを割らない）
    static string TakeFirst(string s, int length)
    {
        if (s.Length <= length) return s;
        if (char.IsHighSurrogate(s[length - 1])) length--;
        return s[..length];
    }
}
