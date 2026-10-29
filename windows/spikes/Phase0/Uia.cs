using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Interop.UIAutomationClient;

namespace Koebumi.Phase0;

/// Mac 版の SurroundingText と同じ形。入力欄のカーソル前後と、同じウィンドウの文字列
record Surrounding(string Before, string After, string Screen, string ScreenAfter)
{
    public const int MaxBefore = 300, MaxAfter = 1000, MaxScreen = 700, MaxScreenAfter = 1000;
}

record ReadResult(
    Surrounding? Text,
    string Focus,
    string Method,
    int Nodes,
    double FocusMs,
    double CaretMs,
    double ScreenMs,
    double TotalMs,
    string Error);

/// UI Automation（COM の IUIAutomation）で、フォーカスのある入力欄とそのウィンドウの文字列を読む。
/// UI のないスレッド（MTA）から呼ぶ。自分のプロセスの窓を UI スレッドから読むと止まることがあるため
sealed class Uia
{
    public readonly IUIAutomation A = new CUIAutomation8();

    static readonly HashSet<int> SkippedTypes =
    [
        UIA_ControlTypeIds.UIA_MenuBarControlTypeId, UIA_ControlTypeIds.UIA_MenuControlTypeId, UIA_ControlTypeIds.UIA_MenuItemControlTypeId,
        UIA_ControlTypeIds.UIA_ButtonControlTypeId, UIA_ControlTypeIds.UIA_SplitButtonControlTypeId, UIA_ControlTypeIds.UIA_ScrollBarControlTypeId,
        UIA_ControlTypeIds.UIA_ToolBarControlTypeId, UIA_ControlTypeIds.UIA_RadioButtonControlTypeId, UIA_ControlTypeIds.UIA_CheckBoxControlTypeId,
        UIA_ControlTypeIds.UIA_ImageControlTypeId, UIA_ControlTypeIds.UIA_TitleBarControlTypeId,
    ];

    public static string TypeName(int id) => id switch
    {
        UIA_ControlTypeIds.UIA_EditControlTypeId => "Edit",
        UIA_ControlTypeIds.UIA_DocumentControlTypeId => "Document",
        UIA_ControlTypeIds.UIA_TextControlTypeId => "Text",
        UIA_ControlTypeIds.UIA_PaneControlTypeId => "Pane",
        UIA_ControlTypeIds.UIA_WindowControlTypeId => "Window",
        UIA_ControlTypeIds.UIA_GroupControlTypeId => "Group",
        UIA_ControlTypeIds.UIA_CustomControlTypeId => "Custom",
        UIA_ControlTypeIds.UIA_ComboBoxControlTypeId => "ComboBox",
        UIA_ControlTypeIds.UIA_ListItemControlTypeId => "ListItem",
        UIA_ControlTypeIds.UIA_TabItemControlTypeId => "TabItem",
        _ => id.ToString(),
    };

    public string Describe(IUIAutomationElement e)
    {
        try
        {
            return $"{TypeName(e.CurrentControlType)} fw={e.CurrentFrameworkId} class={e.CurrentClassName} id={e.CurrentAutomationId} pid={e.CurrentProcessId}"
                + $" text={(e.GetCurrentPattern(UIA_PatternIds.UIA_TextPatternId) != null ? "y" : "n")}"
                + $" text2={(e.GetCurrentPattern(UIA_PatternIds.UIA_TextPattern2Id) != null ? "y" : "n")}"
                + $" value={(e.GetCurrentPattern(UIA_PatternIds.UIA_ValuePatternId) != null ? "y" : "n")}";
        }
        catch (Exception ex) { return "describe failed: " + ex.Message; }
    }

    /// focused を渡さなければ、いまフォーカスのある要素を読む。window を渡さなければ、最前面の窓を読む
    public ReadResult Read(IUIAutomationElement? focused = null, IntPtr window = default, bool includeScreen = true, bool walk = false)
    {
        var sw = Stopwatch.StartNew();
        double focusMs = 0, caretMs = 0, screenMs = 0;
        string method = "", focusInfo = "";
        int nodes = 0;
        try
        {
            int retries = 0;
            if (focused == null)
            {
                focused = A.GetFocusedElement();
                // Chromium（Chrome・Edge・Electron・WebView2）は UI Automation のクライアントが来てからページの木を作る。
                // それまではフォーカスが外側の枠（Pane）になるので、少し待って取り直す
                while (focused != null && retries < 8 && focused.CurrentFrameworkId == "Chrome" && !HasTextPatterns(focused))
                {
                    Thread.Sleep(30);
                    retries++;
                    focused = A.GetFocusedElement();
                }
            }
            focusMs = sw.Elapsed.TotalMilliseconds;
            if (focused == null) return new ReadResult(null, "", "", 0, focusMs, 0, 0, sw.Elapsed.TotalMilliseconds, "フォーカスのある要素がない");
            focusInfo = Describe(focused);
            if (focused.CurrentIsPassword != 0) return new ReadResult(null, focusInfo, "password", 0, focusMs, 0, 0, sw.Elapsed.TotalMilliseconds, "");

            string before = "", after = "";
            var t = sw.Elapsed.TotalMilliseconds;
            (before, after, method) = CaretText(focused);
            if (retries > 0) method += $" (取り直し {retries} 回)";
            caretMs = sw.Elapsed.TotalMilliseconds - t;

            string screen = "", screenAfter = "";
            if (includeScreen)
            {
                t = sw.Elapsed.TotalMilliseconds;
                var hwnd = window != IntPtr.Zero ? window : Native.GetForegroundWindow();
                var root = hwnd != IntPtr.Zero ? A.ElementFromHandle(hwnd) : null;
                if (root != null) (screen, screenAfter, nodes) = walk ? WalkWindow(root, focused) : CachedWindow(root, focused);
                screenMs = sw.Elapsed.TotalMilliseconds - t;
            }
            return new ReadResult(new Surrounding(before, after, screen, screenAfter), focusInfo, method, nodes, focusMs, caretMs, screenMs, sw.Elapsed.TotalMilliseconds, "");
        }
        catch (Exception e)
        {
            return new ReadResult(null, focusInfo, method, nodes, focusMs, caretMs, screenMs, sw.Elapsed.TotalMilliseconds, e.GetType().Name + ": " + e.Message);
        }
    }

    static bool HasTextPatterns(IUIAutomationElement e) =>
        e.GetCurrentPattern(UIA_PatternIds.UIA_TextPatternId) != null || e.GetCurrentPattern(UIA_PatternIds.UIA_ValuePatternId) != null;

    /// カーソル前後の文字列。TextPattern2 のカーソル位置か、TextPattern の選択範囲から、上限の長さまでだけ取り出す
    (string, string, string) CaretText(IUIAutomationElement el)
    {
        IUIAutomationTextRange? caret = null;
        IUIAutomationTextPattern? tp = null;
        string method;
        if (el.GetCurrentPattern(UIA_PatternIds.UIA_TextPattern2Id) is IUIAutomationTextPattern2 tp2)
        {
            tp = tp2;
            caret = tp2.GetCaretRange(out _);
            method = "TextPattern2.GetCaretRange";
            // 選択しているときは選択範囲を使う（カーソルは選択の片端にある）
            var sel = tp2.GetSelection();
            if (sel != null && sel.Length > 0)
            {
                var s = sel.GetElement(0);
                if (s.GetText(1).Length > 0) { caret = s; method = "TextPattern2.GetSelection"; }
            }
        }
        else if (el.GetCurrentPattern(UIA_PatternIds.UIA_TextPatternId) is IUIAutomationTextPattern p)
        {
            tp = p;
            var sel = p.GetSelection();
            if (sel != null && sel.Length > 0) caret = sel.GetElement(0);
            method = "TextPattern.GetSelection";
        }
        else if (el.GetCurrentPattern(UIA_PatternIds.UIA_ValuePatternId) is IUIAutomationValuePattern vp)
        {
            // カーソル位置がわからないので、すべてをカーソルより前とみなす
            var v = vp.CurrentValue ?? "";
            return (v.Length > Surrounding.MaxBefore ? v[^Surrounding.MaxBefore..] : v, "", "ValuePattern (no caret)");
        }
        else return ("", "", "none");

        if (caret == null) return ("", "", method + " (no range)");

        var before = caret.Clone();
        before.MoveEndpointByRange(TextPatternRangeEndpoint.TextPatternRangeEndpoint_End, caret, TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start);
        before.MoveEndpointByUnit(TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start, TextUnit.TextUnit_Character, -Surrounding.MaxBefore);
        var after = caret.Clone();
        after.MoveEndpointByRange(TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start, caret, TextPatternRangeEndpoint.TextPatternRangeEndpoint_End);
        after.MoveEndpointByUnit(TextPatternRangeEndpoint.TextPatternRangeEndpoint_End, TextUnit.TextUnit_Character, Surrounding.MaxAfter);
        // Chromium では、文字単位で動かすと入力欄を越えてページの文字まで入る。入力欄の範囲で切る
        var field = tp.DocumentRange;
        if (before.CompareEndpoints(TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start, field, TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start) < 0)
        {
            before.MoveEndpointByRange(TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start, field, TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start);
            method += " (前を入力欄で切った)";
        }
        if (after.CompareEndpoints(TextPatternRangeEndpoint.TextPatternRangeEndpoint_End, field, TextPatternRangeEndpoint.TextPatternRangeEndpoint_End) > 0)
        {
            after.MoveEndpointByRange(TextPatternRangeEndpoint.TextPatternRangeEndpoint_End, field, TextPatternRangeEndpoint.TextPatternRangeEndpoint_End);
            method += " (後を入力欄で切った)";
        }
        return (before.GetText(Surrounding.MaxBefore * 2) ?? "", after.GetText(Surrounding.MaxAfter * 2) ?? "", method);
    }

    IUIAutomationCacheRequest TreeRequest(TreeScope scope, bool live = false)
    {
        var req = A.CreateCacheRequest();
        req.AddProperty(UIA_PropertyIds.UIA_NamePropertyId);
        req.AddProperty(UIA_PropertyIds.UIA_ControlTypePropertyId);
        req.AddProperty(UIA_PropertyIds.UIA_IsPasswordPropertyId);
        req.AddProperty(UIA_PropertyIds.UIA_RuntimeIdPropertyId);
        req.AddProperty(UIA_PropertyIds.UIA_ValueValuePropertyId);
        req.TreeScope = scope;
        req.TreeFilter = A.ControlViewCondition;
        // 1 段ずつたどるときは、写した要素から子を問い合わせるので、生きた要素にする
        req.AutomationElementMode = live ? AutomationElementMode.AutomationElementMode_Full : AutomationElementMode.AutomationElementMode_None;
        return req;
    }

    static int[] RuntimeId(IUIAutomationElement e, bool cached)
    {
        try
        {
            object v = cached ? e.GetCachedPropertyValue(UIA_PropertyIds.UIA_RuntimeIdPropertyId) : e.GetRuntimeId();
            return v as int[] ?? [];
        }
        catch { return []; }
    }

    /// 窓の要素をまとめて 1 回で写し（キャッシュ）、手元でたどる
    (string, string, int) CachedWindow(IUIAutomationElement root, IUIAutomationElement focused)
    {
        var target = RuntimeId(focused, cached: false);
        var tree = root.BuildUpdatedCache(TreeRequest(TreeScope.TreeScope_Subtree));
        var collector = new Collector(target);
        void Visit(IUIAutomationElement e, int depth)
        {
            if (depth > 60) return;
            if (!collector.Take(e, cached: true)) return;
            var children = e.GetCachedChildren();
            if (children == null) return;
            for (int i = 0; i < children.Length; i++) Visit(children.GetElement(i), depth + 1);
        }
        Visit(tree, 0);
        return collector.Result();
    }

    /// Mac 版と同じく、0.3 秒・2,500 要素の上限を付けて 1 段ずつたどる（応答の遅いアプリで待たせないため）
    (string, string, int) WalkWindow(IUIAutomationElement root, IUIAutomationElement focused)
    {
        var target = RuntimeId(focused, cached: false);
        var req = TreeRequest(TreeScope.TreeScope_Element, live: true);
        var deadline = Stopwatch.StartNew();
        var collector = new Collector(target);
        var trueCondition = A.CreateTrueCondition();
        void Visit(IUIAutomationElement e, int depth)
        {
            if (depth > 40 || collector.Nodes >= 2500 || deadline.ElapsedMilliseconds > 300) return;
            if (!collector.Take(e, cached: true)) return;
            var children = e.FindAllBuildCache(TreeScope.TreeScope_Children, A.ControlViewCondition, req);
            if (children == null) return;
            for (int i = 0; i < children.Length; i++) Visit(children.GetElement(i), depth + 1);
        }
        Visit(root.BuildUpdatedCache(req), 0);
        return collector.Result();
    }

    sealed class Collector(int[] focusedId)
    {
        readonly List<string> before = [], after = [];
        bool passed;
        public int Nodes;

        /// 子をたどるなら true
        public bool Take(IUIAutomationElement e, bool cached)
        {
            Nodes++;
            if (!passed && focusedId.Length > 0 && RuntimeId(e, cached).SequenceEqual(focusedId))
            {
                passed = true;
                return false;
            }
            int type = e.CachedControlType;
            if (SkippedTypes.Contains(type) || e.CachedIsPassword != 0) return false;
            string? text = null;
            if (type == UIA_ControlTypeIds.UIA_TextControlTypeId) text = e.CachedName;
            else if (type == UIA_ControlTypeIds.UIA_EditControlTypeId)
                text = e.GetCachedPropertyValue(UIA_PropertyIds.UIA_ValueValuePropertyId) as string;
            text = text?.Trim();
            if (!string.IsNullOrEmpty(text) && (passed ? after : before) is var list && (list.Count == 0 || list[^1] != text)) list.Add(text);
            return type != UIA_ControlTypeIds.UIA_EditControlTypeId;
        }

        public (string, string, int) Result()
        {
            var b = string.Join("\n", before);
            var a = string.Join("\n", after);
            if (b.Length > Surrounding.MaxScreen) b = b[^Surrounding.MaxScreen..];
            if (a.Length > Surrounding.MaxScreenAfter) a = a[..Surrounding.MaxScreenAfter];
            return (b.Trim(), a.Trim(), Nodes);
        }
    }

    // MARK: - 試験で使う

    /// 窓の中から、条件に合う最初の要素を探す
    public IUIAutomationElement? Find(IntPtr hwnd, Func<IUIAutomationElement, bool> match)
    {
        var root = A.ElementFromHandle(hwnd);
        var all = root.FindAll(TreeScope.TreeScope_Subtree, A.CreateTrueCondition());
        for (int i = 0; i < all.Length; i++)
        {
            var e = all.GetElement(i);
            try { if (match(e)) return e; } catch { }
        }
        return null;
    }

    /// TextPattern か ValuePattern で、要素の文字列をすべて読む
    public static string? AllText(IUIAutomationElement e)
    {
        if (e.GetCurrentPattern(UIA_PatternIds.UIA_TextPatternId) is IUIAutomationTextPattern tp) return tp.DocumentRange.GetText(-1);
        if (e.GetCurrentPattern(UIA_PatternIds.UIA_ValuePatternId) is IUIAutomationValuePattern vp) return vp.CurrentValue;
        return null;
    }

    /// 文書の先頭から offset 文字目にカーソルを置く（TextPattern の Select）
    public static bool PlaceCaret(IUIAutomationElement e, int offset)
    {
        if (e.GetCurrentPattern(UIA_PatternIds.UIA_TextPatternId) is not IUIAutomationTextPattern tp) return false;
        var r = tp.DocumentRange;
        r.MoveEndpointByRange(TextPatternRangeEndpoint.TextPatternRangeEndpoint_End, r, TextPatternRangeEndpoint.TextPatternRangeEndpoint_Start);
        r.Move(TextUnit.TextUnit_Character, offset);
        r.Select();
        return true;
    }
}

/// メールやチャットの中身を見せずに、読み取りの具合を確かめるため、文字を種類に置き換える（Mac 版の --masked と同じ考え）
static class Mask
{
    static readonly string[] Keep = ["さん", "様", "さま", "くん", "君", "氏", "先生", "部長", "課長", "お疲れ様", "お疲れさま", "お世話になって", "よろしく", "Dear", "Hi", "Hello", "Thanks", "Regards", "Koebumi"];

    public static string Apply(string s)
    {
        var sb = new StringBuilder();
        int i = 0;
        while (i < s.Length)
        {
            var keep = Keep.FirstOrDefault(k => string.CompareOrdinal(s, i, k, 0, k.Length) == 0);
            if (keep != null) { sb.Append(keep); i += keep.Length; continue; }
            var c = s[i];
            sb.Append(c switch
            {
                _ when c >= '一' && c <= '鿿' => '漢',
                _ when c >= '぀' && c <= 'ゟ' => 'あ',
                _ when c >= '゠' && c <= 'ヿ' => 'カ',
                _ when char.IsAsciiLetter(c) => 'a',
                _ when char.IsDigit(c) => '0',
                _ when char.IsSurrogate(c) => '?',
                _ => c,
            });
            i++;
        }
        return sb.ToString();
    }

    public static string Short(string s, int max = 80)
    {
        var one = Regex.Replace(s, @"\s+", " ");
        return one.Length <= max ? one : one[..(max / 2)] + " … " + one[^(max / 2)..];
    }
}
