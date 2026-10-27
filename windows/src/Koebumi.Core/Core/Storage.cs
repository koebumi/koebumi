using System.Collections.Concurrent;
using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Koebumi.Core;

/// アプリのローカルデータ置き場。すべて %APPDATA%\Koebumi 以下に、Mac 版と同じ形の JSON で保存する。
public static class Storage
{
    /// テストと開発用のコマンドで、置き場所を別のフォルダにする
    public static string? RootOverride { get; set; }

    public static string Root
    {
        get
        {
            var dir = RootOverride ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Koebumi");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string AudioDir
    {
        get
        {
            var dir = Path.Combine(Root, "Audio");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string File(string name) => Path.Combine(Root, name);

    /// Mac 版の JSONEncoder と同じ形（キーは camelCase、列挙は rawValue の文字列、日時は ISO 8601）
    public static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DictionaryKeyPolicy = null,
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) },
    };

    public static T? Load<T>(string name) => LoadAt<T>(File(name));

    public static T? LoadAt<T>(string path)
    {
        if (!System.IO.File.Exists(path)) return default;
        try
        {
            using var stream = System.IO.File.OpenRead(path);
            return JsonSerializer.Deserialize<T>(stream, Json);
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Koebumi: failed to decode {Path.GetFileName(path)}: {e.Message}");
            return default;
        }
    }

    public static void Save<T>(T value, string name) => SaveAt(value, File(name));

    /// いったん別のファイルに書いてから置き換える（途中で落ちても前の内容が残る）
    public static void SaveAt<T>(T value, string path)
    {
        try
        {
            var tmp = path + ".tmp";
            System.IO.File.WriteAllBytes(tmp, JsonSerializer.SerializeToUtf8Bytes(value, Json));
            System.IO.File.Move(tmp, path, overwrite: true);
        }
        catch (Exception e)
        {
            Debug.WriteLine($"Koebumi: failed to save {Path.GetFileName(path)}: {e.Message}");
        }
    }

    /// ファイルの更新日時（ないときは null）。ほかのプロセスが書き換えたかを見分けるのに使う
    public static DateTime? ModificationDate(string path) =>
        System.IO.File.Exists(path) ? System.IO.File.GetLastWriteTimeUtc(path) : null;

    public static void DeleteAll()
    {
        try { Directory.Delete(Root, recursive: true); } catch { }
    }

    /// JSON に書くときの列挙の文字列（設定の辞書のキーに使う。例: AppCategory.Email → "email"）
    public static string Raw<T>(T value) where T : struct, Enum =>
        JsonSerializer.Serialize(value, Json).Trim('"');

    public static T? ParseRaw<T>(string raw) where T : struct, Enum
    {
        try { return JsonSerializer.Deserialize<T>($"\"{raw}\"", Json); }
        catch (JsonException) { return null; }
    }
}

/// 新しい項目を足しても古いファイルを読めるよう、欠けたキーや読めない値は既定値のままにする
/// （Mac 版の `(try? c.decodeIfPresent(...)) ?? 既定値` と同じ）。型に [JsonConverter(typeof(TolerantConverter&lt;T&gt;))] で付ける
public sealed class TolerantConverter<T> : JsonConverter<T> where T : class, new()
{
    static readonly ConcurrentDictionary<Type, PropertyInfo[]> Properties = new();

    static PropertyInfo[] Of(Type type) => Properties.GetOrAdd(type, t => t
        .GetProperties(BindingFlags.Public | BindingFlags.Instance)
        .Where(p => p.CanRead && p.CanWrite && p.GetIndexParameters().Length == 0 && p.GetCustomAttribute<JsonIgnoreAttribute>() == null)
        .ToArray());

    static string NameOf(PropertyInfo p, JsonSerializerOptions options) =>
        p.GetCustomAttribute<JsonPropertyNameAttribute>()?.Name ?? options.PropertyNamingPolicy?.ConvertName(p.Name) ?? p.Name;

    public override T? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (JsonNode.Parse(ref reader) is not JsonObject obj) return new T();
        var value = new T();
        foreach (var p in Of(typeof(T)))
        {
            if (!obj.TryGetPropertyValue(NameOf(p, options), out var node)) continue;
            try { p.SetValue(value, node?.Deserialize(p.PropertyType, options)); }
            catch (Exception e) when (e is JsonException or InvalidOperationException or NotSupportedException or ArgumentException) { }
        }
        return value;
    }

    public override void Write(Utf8JsonWriter writer, T value, JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        foreach (var p in Of(typeof(T)).OrderBy(p => NameOf(p, options), StringComparer.Ordinal))
        {
            var v = p.GetValue(value);
            if (v == null && options.DefaultIgnoreCondition == JsonIgnoreCondition.WhenWritingNull) continue;
            writer.WritePropertyName(NameOf(p, options));
            JsonSerializer.Serialize(writer, v, p.PropertyType, options);
        }
        writer.WriteEndObject();
    }
}
