using System.Text.Encodings.Web;
using System.Text.Json;

namespace Koebumi.Cli;

/// 報告に書く項目。Mac 版の JSONSerialization（.sortedKeys）と同じく、キーを並べ替えて出す
sealed class Fields() : SortedDictionary<string, object?>(StringComparer.Ordinal);

/// JSON の出力。日本語はそのまま書き、改行は LF にする（Git Bash のパイプで ^M が付かないように）
static class JsonOutput
{
    static readonly JsonSerializerOptions CompactOptions = new()
    {
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        NewLine = "\n",
    };

    static readonly JsonSerializerOptions PrettyOptions = new(CompactOptions) { WriteIndented = true };

    public static string Compact(Fields fields) => JsonSerializer.Serialize<object>(fields, CompactOptions);

    public static string Pretty(Fields fields) => JsonSerializer.Serialize<object>(fields, PrettyOptions);

    /// 秒は小数点以下 3 桁まで（ミリ秒）にする
    public static double Seconds(TimeSpan elapsed) => Math.Round(elapsed.TotalSeconds, 3);
}
