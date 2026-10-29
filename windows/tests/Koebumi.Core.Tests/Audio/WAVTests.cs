using Koebumi.Core;

namespace Koebumi.Core.Tests;

public class WAVTests
{
    [Fact]
    public void RoundTrips()
    {
        var samples = Enumerable.Range(0, 1600).Select(i => MathF.Sin(i / 10f) * 0.5f).ToArray();
        var data = WAV.Encode(new RecordedAudio(samples));
        Assert.Equal(44 + samples.Length * 2, data.Length);
        var decoded = WAV.Decode(data)!;
        Assert.NotNull(decoded);
        Assert.Equal(16000, decoded.SampleRate);
        Assert.Equal(samples.Length, decoded.Samples.Length);
        Assert.True(decoded.Samples.Zip(samples).All(p => Math.Abs(p.First - p.Second) < 0.001f));
    }

    [Fact]
    public void SilenceAndNormalization()
    {
        Assert.True(new RecordedAudio(Enumerable.Repeat(0.001f, 16000).ToArray()).IsSilent);
        Assert.True(new RecordedAudio(Enumerable.Repeat(0.2f, 1000).ToArray()).IsSilent);  // 短すぎる
        var quiet = new RecordedAudio(Enumerable.Repeat(0.05f, 16000).ToArray());
        Assert.False(quiet.IsSilent);
        Assert.True(Math.Abs(quiet.Normalized().Peak - 0.8f) < 0.01f);  // 最大 16 倍まで
    }

    // Mac 版の LocalSpeechTests.longAudioIsSplitAtTheQuietestPause
    [Fact]
    public void LongAudioIsSplitAtTheQuietestPause()
    {
        // 1 秒の音 → 0.5 秒の無音 → 1 秒の音 → 0.5 秒の無音 → 1 秒の音（16 kHz で 4 秒）
        var tone = Enumerable.Range(0, 16000).Select(i => (float)Math.Sin(i * 0.3) * 0.5f).ToArray();
        var pause = new float[8000];
        var audio = new RecordedAudio([.. tone, .. pause, .. tone, .. pause, .. tone]);
        var parts = audio.Split(2);
        Assert.All(parts, p => Assert.True(p.Duration <= 2));
        Assert.Equal(audio.Samples, parts.SelectMany(p => p.Samples).ToArray());
        // 区切りは無音の中に置く
        int cut = 0;
        foreach (var part in parts.SkipLast(1))
        {
            cut += part.Samples.Length;
            Assert.Equal(0f, audio.Samples[cut]);
        }
        Assert.Single(new RecordedAudio(tone).Split(15));
    }

    [Fact]
    public void EncodeWritesA16BitMonoHeaderAndClampsSamples()
    {
        var data = WAV.Encode(new RecordedAudio([0f, 1f, -1f, 2f, -2f]));
        Assert.Equal("RIFF", System.Text.Encoding.ASCII.GetString(data, 0, 4));
        Assert.Equal("WAVE", System.Text.Encoding.ASCII.GetString(data, 8, 4));
        Assert.Equal(36u + 10, BitConverter.ToUInt32(data, 4));
        Assert.Equal(1, BitConverter.ToUInt16(data, 22));
        Assert.Equal(16000u, BitConverter.ToUInt32(data, 24));
        Assert.Equal(32000u, BitConverter.ToUInt32(data, 28));
        Assert.Equal(16, BitConverter.ToUInt16(data, 34));
        Assert.Equal(10u, BitConverter.ToUInt32(data, 40));
        Assert.Equal<short>([0, 32767, -32767, 32767, -32767], Enumerable.Range(0, 5).Select(i => BitConverter.ToInt16(data, 44 + i * 2)));
    }

    [Fact]
    public void DecodeRejectsDataThatIsNotWav()
    {
        Assert.Null(WAV.Decode(new byte[10]));
        Assert.Null(WAV.Decode(new byte[100]));
        Assert.Null(WAV.Decode(WAV.Encode(new RecordedAudio([0.5f])).AsSpan(0, 36)));
        // 「data」の部分がない
        var noData = WAV.Encode(new RecordedAudio([0.5f]));
        "junk"u8.CopyTo(noData.AsSpan(36));
        Assert.Null(WAV.Decode(noData));
    }

    [Fact]
    public void DecodeKeepsTheSampleRateAndReadsOnlyTheFirstChannel()
    {
        var mono = WAV.Encode(new RecordedAudio([0.25f, -0.5f, 0.75f, 0f], 8000));
        Assert.Equal(8000, WAV.Decode(mono)!.SampleRate);
        // 2 チャンネルに書き換える（左右の順に 4 サンプル = 2 フレーム）
        var stereo = (byte[])mono.Clone();
        BitConverter.GetBytes((ushort)2).CopyTo(stereo, 22);
        var decoded = WAV.Decode(stereo)!;
        Assert.Equal(2, decoded.Samples.Length);
        Assert.True(Math.Abs(decoded.Samples[0] - 0.25f) < 0.001f);
        Assert.True(Math.Abs(decoded.Samples[1] - 0.75f) < 0.001f);
    }

    [Fact]
    public void DecodeStopsAtTheEndOfTruncatedData()
    {
        var data = WAV.Encode(new RecordedAudio([0.1f, 0.2f, 0.3f, 0.4f]));
        var decoded = WAV.Decode(data.AsSpan(0, 44 + 5))!;  // 3 サンプル目は半分しかない
        Assert.Equal(2, decoded.Samples.Length);
    }

    [Fact]
    public void EmptyAudioHasNoPeakOrRms()
    {
        var empty = new RecordedAudio([]);
        Assert.Equal(0f, empty.Peak);
        Assert.Equal(0f, empty.Rms);
        Assert.True(empty.IsSilent);
        Assert.Same(empty, empty.Normalized());
        Assert.Equal(0.5f, new RecordedAudio([0.5f, -0.5f]).Rms);
    }
}
