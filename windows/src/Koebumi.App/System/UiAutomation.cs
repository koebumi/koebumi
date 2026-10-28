using Interop.UIAutomationClient;

namespace Koebumi.App;

/// COM の IUIAutomation を 1 つだけ作って使い回す。MTA のスレッド（スレッド プール）で作られ、どのスレッドからも使える
internal static class UiAutomation
{
    static readonly Lazy<IUIAutomation> instance = new(() => Task.Run<IUIAutomation>(() => new CUIAutomation8()).GetAwaiter().GetResult());

    public static IUIAutomation Instance => instance.Value;
}
