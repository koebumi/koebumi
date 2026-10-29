using System.Diagnostics;
using Microsoft.Win32;

namespace Koebumi.App;

/// Windows の設定 > プライバシーとセキュリティ > マイク のアクセス許可。Mac 版の Permissions のマイクの部分に当たる。
/// オフのときは録音を始めても例外にならず、無音しか届かないことがあるので、録音の前にこの設定を見る
internal static class MicrophoneAccess
{
    const string ConsentKey = @"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone";

    /// 「マイクへのアクセス」（PC 全体）・「アプリがマイクにアクセスできるようにする」・「デスクトップ アプリがマイクにアクセスできるようにする」のどれかがオフ
    public static bool IsDenied =>
        Denied(Registry.LocalMachine, ConsentKey) || Denied(Registry.CurrentUser, ConsentKey) || Denied(Registry.CurrentUser, ConsentKey + @"\NonPackaged");

    static bool Denied(RegistryKey root, string path)
    {
        try
        {
            using var key = root.OpenSubKey(path);
            return string.Equals(key?.GetValue("Value") as string, "Deny", StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception)
        {
            return false;
        }
    }

    /// 設定のマイクのページを開く
    public static void OpenSettings()
    {
        try
        {
            Process.Start(new ProcessStartInfo("ms-settings:privacy-microphone") { UseShellExecute = true });
        }
        catch (Exception e)
        {
            Debug.WriteLine($"[Koebumi] マイクの設定を開けない: {e.Message}");
        }
    }
}
