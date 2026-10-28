using Koebumi.Core;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace Koebumi.App;

public sealed class AudioCaptureException(string message, Exception? inner = null) : Exception(message, inner);

/// WASAPI で録音し、16 kHz モノラルの float に変換して溜める。Mac 版の AudioRecorder に当たる。
/// Level と Error は録音のスレッドから呼ばれる（UI の更新は Dispatcher へ移す）
public sealed class AudioRecorder : IDisposable
{
    const int TargetRate = 16000;
    /// 音量を知らせる間隔（約 20 Hz）のサンプル数
    const int LevelWindow = TargetRate / 20;

    readonly object gate = new();
    readonly List<float> samples = [];
    WasapiCapture? capture;
    MMDevice? device;
    WaveFormat? format;
    BufferedWaveProvider? buffer;
    ISampleProvider? resampler;
    ManualResetEventSlim? stopped;
    bool stopRequested;
    float[] mono = [];
    byte[] monoBytes = [];
    readonly float[] converted = new float[4096];
    float[] levels = new float[8];
    double levelSum;
    int levelCount;

    /// 声の大きさ（0〜1）。約 20 回/秒
    public event Action<float>? Level;
    /// 録音中にデバイスが外れるなどして、Stop の前に止まった
    public event Action<Exception>? Error;

    public bool IsRecording => capture != null;
    /// 録音しているデバイスの名前
    public string? DeviceName { get; private set; }

    /// deviceId（AudioDevices の Id）のデバイスで録音を始める。null か、見つからないときは既定のデバイス。
    /// 始められなければ AudioCaptureException
    public void Start(string? deviceId = null)
    {
        if (capture != null) Stop();
        // NAudio は作ったときの SynchronizationContext に RecordingStopped を届ける。UI スレッドで作ると Stop で待てなくなるので外す
        var context = SynchronizationContext.Current;
        SynchronizationContext.SetSynchronizationContext(null);
        try
        {
            device = Resolve(deviceId);
            capture = new WasapiCapture(device, false, 100);
            format = capture.WaveFormat is WaveFormatExtensible extensible ? extensible.ToStandardWaveFormat() : capture.WaveFormat;
            // 録音の形式を 1 チャンネルの float にそろえてから、WDL で 16 kHz にする
            buffer = new BufferedWaveProvider(WaveFormat.CreateIeeeFloatWaveFormat(format.SampleRate, 1), TimeSpan.FromSeconds(5))
            {
                ReadFully = false,
                DiscardOnBufferOverflow = true,
            };
            resampler = new WdlResamplingSampleProvider(buffer.ToSampleProvider(), TargetRate);
            lock (gate)
            {
                samples.Clear();
                levelSum = 0;
                levelCount = 0;
            }
            stopped = new ManualResetEventSlim();
            stopRequested = false;
            capture.DataAvailable += OnData;
            capture.RecordingStopped += OnStopped;
            DeviceName = device.FriendlyName;
            capture.StartRecording();
        }
        catch (Exception e)
        {
            Release();
            throw e as AudioCaptureException ?? new AudioCaptureException($"マイクを開始できません（{e.Message}）", e);
        }
        finally
        {
            SynchronizationContext.SetSynchronizationContext(context);
        }
    }

    /// 録音を止めて、ここまでの音声を返す。録音していなければ空の音声
    public RecordedAudio Stop()
    {
        var c = capture;
        if (c == null) return new RecordedAudio([]);
        stopRequested = true;
        try
        {
            c.StopRecording();
            stopped?.Wait(TimeSpan.FromSeconds(2));
        }
        catch (Exception)
        {
            // 止めるときの失敗は、溜めた音声を返すことを妨げない
        }
        Release();
        lock (gate)
        {
            var audio = new RecordedAudio([.. samples], TargetRate);
            samples.Clear();
            return audio;
        }
    }

    public void Dispose() => Stop();

    MMDevice Resolve(string? deviceId)
    {
        var enumerator = new MMDeviceEnumerator();
        try
        {
            if (!string.IsNullOrEmpty(deviceId))
            {
                try
                {
                    var found = enumerator.GetDevice(deviceId);
                    if (found.State == DeviceState.Active) return found;
                    found.Dispose();
                }
                catch (Exception)
                {
                    // 外されたマイクなど。既定のデバイスで録音する
                }
            }
            if (!enumerator.HasDefaultAudioEndpoint(DataFlow.Capture, Role.Console))
                throw new AudioCaptureException("マイクが見つかりません");
            return enumerator.GetDefaultAudioEndpoint(DataFlow.Capture, Role.Console);
        }
        finally { enumerator.Dispose(); }
    }

    void Release()
    {
        var c = capture;
        capture = null;
        if (c != null)
        {
            c.DataAvailable -= OnData;
            c.RecordingStopped -= OnStopped;
            try { c.Dispose(); } catch (Exception) { }
        }
        device?.Dispose();
        device = null;
        stopped?.Dispose();
        stopped = null;
        buffer = null;
        resampler = null;
        DeviceName = null;
    }

    void OnStopped(object? sender, StoppedEventArgs e)
    {
        stopped?.Set();
        if (!stopRequested && e.Exception != null) Error?.Invoke(e.Exception);
    }

    void OnData(object? sender, WaveInEventArgs e)
    {
        if (format == null || buffer == null || resampler == null || e.BytesRecorded == 0) return;
        int channels = Math.Max(format.Channels, 1);
        int bytesPerSample = format.BitsPerSample / 8;
        int frames = e.BytesRecorded / (bytesPerSample * channels);
        if (mono.Length < frames)
        {
            mono = new float[frames];
            monoBytes = new byte[frames * sizeof(float)];
        }
        bool isFloat = format.Encoding == WaveFormatEncoding.IeeeFloat;
        for (int f = 0; f < frames; f++)
        {
            float sum = 0;
            for (int ch = 0; ch < channels; ch++) sum += Sample(e.Buffer, (f * channels + ch) * bytesPerSample, bytesPerSample, isFloat);
            mono[f] = sum / channels;
        }
        Buffer.BlockCopy(mono, 0, monoBytes, 0, frames * sizeof(float));
        buffer.AddSamples(monoBytes, 0, frames * sizeof(float));

        int n;
        while ((n = resampler.Read(converted, 0, converted.Length)) > 0) Append(converted, n);
    }

    static float Sample(byte[] data, int offset, int bytes, bool isFloat) => bytes switch
    {
        4 when isFloat => BitConverter.ToSingle(data, offset),
        4 => BitConverter.ToInt32(data, offset) / 2147483648f,
        3 => ((data[offset] << 8) | (data[offset + 1] << 16) | (data[offset + 2] << 24)) / 2147483648f,
        2 => BitConverter.ToInt16(data, offset) / 32768f,
        _ => 0f,
    };

    void Append(float[] block, int count)
    {
        int levelsReady = 0;
        lock (gate)
        {
            for (int i = 0; i < count; i++)
            {
                samples.Add(block[i]);
                levelSum += block[i] * block[i];
                if (++levelCount < LevelWindow) continue;
                // 声の大きさを見やすい 0...1 に変換（約 -50 dB を 0 とする。Mac 版と同じ）
                var db = 20 * Math.Log10(Math.Max(Math.Sqrt(levelSum / levelCount), 1e-6));
                if (levelsReady == levels.Length) Array.Resize(ref levels, levels.Length * 2);
                levels[levelsReady++] = (float)Math.Clamp((db + 50) / 45, 0, 1);
                levelSum = 0;
                levelCount = 0;
            }
        }
        for (int i = 0; i < levelsReady; i++)
        {
            try { Level?.Invoke(levels[i]); } catch (Exception) { }
        }
    }
}
