using NAudio.Wave;
using NAudio.Wave.SampleProviders;
using Koebumi.Core;

namespace Koebumi.Cli;

/// 音声ファイルを 16 kHz モノラルの RecordedAudio にする。Mac 版の CLI.loadAudio に当たる。
/// 16 ビット PCM のモノラル WAV は Core の WAV.Decode で読む。それ以外（ステレオ、24 ビット、mp3、m4a、flac など）は Media Foundation で読む
static class AudioLoader
{
    const int TargetRate = 16000;

    public static RecordedAudio Load(string path)
    {
        if (!File.Exists(path)) throw new FileNotFoundException($"audio file not found: {path}");
        var bytes = File.ReadAllBytes(path);
        float[] samples;
        int rate;
        if (IsMono16BitPcm(bytes) && WAV.Decode(bytes) is { } wav)
        {
            samples = wav.Samples;
            rate = (int)wav.SampleRate;
        }
        else
        {
            (samples, rate) = DecodeWithMediaFoundation(path);
        }
        if (samples.Length == 0) throw new InvalidDataException($"no audio in {path}");
        return new RecordedAudio(Resample(samples, rate), TargetRate);
    }

    static bool IsMono16BitPcm(byte[] bytes)
    {
        try
        {
            using var reader = new WaveFileReader(new MemoryStream(bytes));
            var format = reader.WaveFormat;
            return format.Encoding == WaveFormatEncoding.Pcm && format.Channels == 1 && format.BitsPerSample == 16;
        }
        catch (Exception)
        {
            // WAV でないファイルは Media Foundation に任せる
            return false;
        }
    }

    /// 全チャンネルの平均をとって、モノラルにする
    static (float[] Samples, int Rate) DecodeWithMediaFoundation(string path)
    {
        try
        {
            using var reader = new MediaFoundationReader(path);
            var source = reader.ToSampleProvider();
            int channels = source.WaveFormat.Channels, rate = source.WaveFormat.SampleRate;
            var mono = new List<float>();
            var buffer = new float[rate * channels];
            int read;
            while ((read = source.Read(buffer, 0, buffer.Length)) > 0)
            {
                for (int frame = 0; frame < read / channels; frame++)
                {
                    float sum = 0;
                    for (int c = 0; c < channels; c++) sum += buffer[frame * channels + c];
                    mono.Add(sum / channels);
                }
            }
            return ([.. mono], rate);
        }
        catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException or FormatException or IOException)
        {
            throw new InvalidDataException($"cannot decode {path}: {e.Message} (WAV, mp3, m4a and other formats that Windows Media Foundation can read are supported)", e);
        }
    }

    /// アプリの録音と同じ NAudio の WDL で 16 kHz にする
    static float[] Resample(float[] mono, int rate)
    {
        if (rate == TargetRate) return mono;
        var resampler = new WdlResamplingSampleProvider(new ArraySampleProvider(mono, rate), TargetRate);
        var output = new List<float>((int)((long)mono.Length * TargetRate / rate) + 1024);
        var buffer = new float[TargetRate];
        int read;
        while ((read = resampler.Read(buffer, 0, buffer.Length)) > 0) output.AddRange(buffer.AsSpan(0, read));
        return [.. output];
    }

    sealed class ArraySampleProvider(float[] samples, int rate) : ISampleProvider
    {
        int position;

        public WaveFormat WaveFormat { get; } = WaveFormat.CreateIeeeFloatWaveFormat(rate, 1);

        public int Read(float[] buffer, int offset, int count)
        {
            int n = Math.Min(count, samples.Length - position);
            Array.Copy(samples, position, buffer, offset, n);
            position += n;
            return n;
        }
    }
}
