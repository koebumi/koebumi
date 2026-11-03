import AudioCommon
import Foundation

/// この Mac のモデルの置き場所（~/Library/Application Support/Koebumi/qwen3-speech/models/<repo>）。
/// speech-swift の既定は ~/Library/Caches/qwen3-speech だが、Caches は消えても作り直せるものの置き場所で、
/// ストレージの空きを作る機能やお掃除アプリが中身を消すことがある。消えると、アップデートの後などに数百 MB〜2 GB を取り直すことになる（#9）。
/// そこで設定や履歴と同じ Application Support に置く。もう一度ダウンロードできるので、Time Machine のバックアップには入れない
enum LocalModelLocation {
    /// speech-swift は、この環境変数のフォルダの下の qwen3-speech にモデルを置く（HuggingFaceDownloader.getCacheDirectory）
    static let environmentKey = "QWEN3_CACHE_DIR"
    static let folderName = "qwen3-speech"

    /// 起動してすぐ、モデルのファイルに触る前に呼ぶ。Caches にある Koebumi のモデルを移してから、speech-swift に置き場所を教える。
    /// 環境変数で置き場所を指定して起動したとき（開発用）は、それに従い、何も移さない
    static func activate() {
        let override = ProcessInfo.processInfo.environment[environmentKey] ?? ""
        guard override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        prepare(oldBase: caches.appendingPathComponent(folderName, isDirectory: true), root: Storage.root)
        setenv(environmentKey, Storage.root.path, 1)
    }

    /// root の下にモデルの置き場所を作り、古い置き場所からモデルを移す。新しい置き場所を返す
    @discardableResult
    static func prepare(oldBase: URL, root: URL) -> URL {
        let base = root.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        excludeFromBackup(base)
        moveModels(from: oldBase, to: base)
        return base
    }

    /// Koebumi がダウンロードを終えたモデル（印のあるもの）だけを移す。ほかのアプリが speech-swift で取ってきたモデルと、途中で止まったダウンロードは残す。
    /// 同じボリュームの中の移動なので、大きさによらずすぐ終わる。移したモデルを返す
    @discardableResult
    static func moveModels(from oldBase: URL, to newBase: URL,
                           models: [LocalSpeechModel] = LocalSpeechModel.allCases) -> [LocalSpeechModel] {
        let fm = FileManager.default
        var moved: [LocalSpeechModel] = []
        for model in models {
            let dest = directory(of: model, in: newBase)
            if isReady(dest) { continue }
            // speech-swift の今の置き方（models/<repo>）と、古い置き方（repo の / を _ にした名前）
            let candidates = [
                directory(of: model, in: oldBase),
                oldBase.appendingPathComponent(HuggingFaceDownloader.sanitizedCacheKey(for: model.repo), isDirectory: true),
            ]
            guard let source = candidates.first(where: isReady) else { continue }
            do {
                // 途中まで取ってきたファイルや空のフォルダがあれば、移すものに置き換える
                if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: source, to: dest)
                moved.append(model)
                NSLog("Koebumi: moved \(model.rawValue) from \(source.path) to \(dest.path)")
            } catch {
                NSLog("Koebumi: could not move \(model.rawValue) from \(source.path): \(error)")
            }
        }
        return moved
    }

    /// speech-swift（swift-transformers の Hub）がモデルを置くフォルダ
    static func directory(of model: LocalSpeechModel, in base: URL) -> URL {
        base.appendingPathComponent("models", isDirectory: true).appendingPathComponent(model.repo, isDirectory: true)
    }

    private static func isReady(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(LocalSpeechModel.readyMarkerName).path)
    }

    private static func excludeFromBackup(_ directory: URL) {
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try url.setResourceValues(values)
        } catch {
            NSLog("Koebumi: could not exclude \(directory.path) from backups: \(error)")
        }
    }
}
