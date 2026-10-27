namespace Koebumi.Core.Tests;

/// ファイルに書くテストは、この 1 つのコレクションの中で順に動かす（Storage.RootOverride は全体で 1 つなので、ほかのテストと同時に動かさない）
[CollectionDefinition(Name, DisableParallelization = true)]
public class DataFilesCollection
{
    public const string Name = "Data files";
}

/// テストごとの一時フォルダ。閉じると消える
internal sealed class DataTestFolder : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "koebumi-data-" + Guid.NewGuid().ToString("N"));

    public DataTestFolder() => Directory.CreateDirectory(Path);

    public string File(string name) => System.IO.Path.Combine(Path, name);

    public void Dispose()
    {
        try { Directory.Delete(Path, recursive: true); } catch { }
    }
}
