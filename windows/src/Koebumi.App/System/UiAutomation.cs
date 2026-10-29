using System.Diagnostics;
using Interop.UIAutomationClient;

namespace Koebumi.App;

/// COM の IUIAutomation を 1 つだけ作って使い回す。MTA のスレッド（スレッド プール）で作られ、どのスレッドからも使える
internal static class UiAutomation
{
    static readonly Lazy<IUIAutomation> instance = new(() => Task.Run<IUIAutomation>(() => new CUIAutomation8()).GetAwaiter().GetResult());

    public static IUIAutomation Instance => instance.Value;

    /// フォーカスのある要素。MTA のスレッドで呼ぶ。
    /// Chromium（Chrome・Edge・Electron・WebView2）は UI Automation のクライアントが来てからページの木を作る。
    /// それまではフォーカスが外側の枠（Pane）になり、テキストのパターンがないので、30 ms 待って取り直す（budgetMs まで、最大 8 回）
    public static IUIAutomationElement? FocusedElement(int budgetMs, out int retries)
    {
        var clock = Stopwatch.StartNew();
        var focused = Instance.GetFocusedElement();
        retries = 0;
        while (focused != null && retries < 8 && clock.ElapsedMilliseconds < budgetMs
            && focused.CurrentFrameworkId == "Chrome" && !HasTextPatterns(focused))
        {
            Thread.Sleep(30);
            retries++;
            focused = Instance.GetFocusedElement();
        }
        return focused;
    }

    static bool HasTextPatterns(IUIAutomationElement e) =>
        e.GetCurrentPattern(UIA_PatternIds.UIA_TextPatternId) != null || e.GetCurrentPattern(UIA_PatternIds.UIA_ValuePatternId) != null;
}
