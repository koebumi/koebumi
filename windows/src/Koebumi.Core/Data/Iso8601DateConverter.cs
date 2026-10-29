using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Koebumi.Core;

/// Mac 版の JSONEncoder の `.iso8601` と同じ形（秒までの UTC。例: 2026-10-27T01:23:45Z）で日時を読み書きする。
/// 小数秒を付けないので、Mac 版の JSONDecoder でも読める。履歴と辞書の日時に [JsonConverter(typeof(Iso8601DateConverter))] で付ける
public sealed class Iso8601DateConverter : JsonConverter<DateTimeOffset>
{
    public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
        reader.GetDateTimeOffset();

    public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture));
}
