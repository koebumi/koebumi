using NAudio.CoreAudioApi;

namespace Koebumi.App;

/// Id は AppSettings.MicrophoneId に保存する値（WASAPI のエンドポイント ID）
public sealed record AudioDevice(string Id, string Name, bool IsDefault);

/// 録音できるデバイス（マイク）の一覧。Mac 版の AudioDevices に当たる（入力中のミュートはフェーズ 2）
public static class AudioDevices
{
    /// 使える録音デバイス。既定のデバイスが先頭。見つからなければ空
    public static IReadOnlyList<AudioDevice> Capture()
    {
        var list = new List<AudioDevice>();
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            var defaultId = DefaultId(enumerator);
            foreach (var device in enumerator.EnumerateAudioEndPoints(DataFlow.Capture, DeviceState.Active))
            {
                using (device) list.Add(new AudioDevice(device.ID, device.FriendlyName, device.ID == defaultId));
            }
        }
        catch (Exception)
        {
            // デバイスの一覧を取れないときは、空の一覧として扱う
        }
        return [.. list.OrderByDescending(d => d.IsDefault).ThenBy(d => d.Name, StringComparer.CurrentCultureIgnoreCase)];
    }

    /// 既定の録音デバイスの ID。なければ null
    public static string? DefaultId()
    {
        try
        {
            using var enumerator = new MMDeviceEnumerator();
            return DefaultId(enumerator);
        }
        catch (Exception)
        {
            return null;
        }
    }

    static string? DefaultId(MMDeviceEnumerator enumerator)
    {
        if (!enumerator.HasDefaultAudioEndpoint(DataFlow.Capture, Role.Console)) return null;
        using var device = enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
        return device.ID;
    }
}
