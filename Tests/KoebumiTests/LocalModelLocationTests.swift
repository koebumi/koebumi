import Foundation
import Testing
@testable import Koebumi

/// 古い版が ~/Library/Caches/qwen3-speech に置いたモデルを、Application Support に移す（#9）
@Suite struct LocalModelLocationTests {
    private let fm = FileManager.default

    private func makeBase() throws -> URL {
        let base = fm.temporaryDirectory.appendingPathComponent("koebumi-models-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func write(_ text: String, _ url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// ダウンロードを終えたモデル（印のあるフォルダ）を作る
    private func makeReady(_ dir: URL, weights: String = "weights") throws {
        try write(weights, dir.appendingPathComponent("model.safetensors"))
        try write("", dir.appendingPathComponent(LocalSpeechModel.readyMarkerName))
    }

    @Test func movesDownloadedModelsAndLeavesTheRest() throws {
        let base = try makeBase()
        defer { try? fm.removeItem(at: base) }
        let old = base.appendingPathComponent("Caches/qwen3-speech")
        let new = base.appendingPathComponent("Koebumi/qwen3-speech")
        try makeReady(LocalModelLocation.directory(of: .qwen3Small, in: old))
        // 途中で止まったダウンロード（印がない）
        try write("partial", LocalModelLocation.directory(of: .qwen3Large, in: old).appendingPathComponent("model.safetensors"))
        // ほかのアプリが speech-swift で取ってきたモデル
        let other = old.appendingPathComponent("models/someone/Other-Model")
        try makeReady(other)

        #expect(LocalModelLocation.moveModels(from: old, to: new) == [.qwen3Small])

        let moved = LocalModelLocation.directory(of: .qwen3Small, in: new)
        #expect(try read(moved.appendingPathComponent("model.safetensors")) == "weights")
        #expect(fm.fileExists(atPath: moved.appendingPathComponent(LocalSpeechModel.readyMarkerName).path))
        #expect(!fm.fileExists(atPath: LocalModelLocation.directory(of: .qwen3Small, in: old).path))
        #expect(fm.fileExists(atPath: LocalModelLocation.directory(of: .qwen3Large, in: old).path))
        #expect(!fm.fileExists(atPath: LocalModelLocation.directory(of: .qwen3Large, in: new).path))
        #expect(fm.fileExists(atPath: other.path))
    }

    @Test func replacesAPartialDownloadInTheNewPlace() throws {
        let base = try makeBase()
        defer { try? fm.removeItem(at: base) }
        let old = base.appendingPathComponent("Caches/qwen3-speech")
        let new = base.appendingPathComponent("Koebumi/qwen3-speech")
        try makeReady(LocalModelLocation.directory(of: .haas, in: old), weights: "complete")
        try write("partial", LocalModelLocation.directory(of: .haas, in: new).appendingPathComponent("model.safetensors"))

        #expect(LocalModelLocation.moveModels(from: old, to: new) == [.haas])
        #expect(try read(LocalModelLocation.directory(of: .haas, in: new).appendingPathComponent("model.safetensors")) == "complete")
    }

    @Test func keepsAModelAlreadyInTheNewPlace() throws {
        let base = try makeBase()
        defer { try? fm.removeItem(at: base) }
        let old = base.appendingPathComponent("Caches/qwen3-speech")
        let new = base.appendingPathComponent("Koebumi/qwen3-speech")
        try makeReady(LocalModelLocation.directory(of: .whisperTurbo, in: old), weights: "old")
        try makeReady(LocalModelLocation.directory(of: .whisperTurbo, in: new), weights: "new")

        #expect(LocalModelLocation.moveModels(from: old, to: new).isEmpty)
        #expect(try read(LocalModelLocation.directory(of: .whisperTurbo, in: new).appendingPathComponent("model.safetensors")) == "new")
        #expect(fm.fileExists(atPath: LocalModelLocation.directory(of: .whisperTurbo, in: old).path))
    }

    @Test func movesTheOldFlatLayout() throws {
        // speech-swift の古い置き方: qwen3-speech/aufklarer_Qwen3-ASR-0.6B-MLX-4bit
        let base = try makeBase()
        defer { try? fm.removeItem(at: base) }
        let old = base.appendingPathComponent("Caches/qwen3-speech")
        let new = base.appendingPathComponent("Koebumi/qwen3-speech")
        try makeReady(old.appendingPathComponent("aufklarer_Qwen3-ASR-0.6B-MLX-4bit"))

        #expect(LocalModelLocation.moveModels(from: old, to: new) == [.qwen3Small])
        #expect(try read(LocalModelLocation.directory(of: .qwen3Small, in: new).appendingPathComponent("model.safetensors")) == "weights")
    }

    @Test func preparesAFolderLeftOutOfBackups() throws {
        let base = try makeBase()
        defer { try? fm.removeItem(at: base) }
        let old = base.appendingPathComponent("Caches/qwen3-speech")
        try makeReady(LocalModelLocation.directory(of: .granite, in: old))

        let new = LocalModelLocation.prepare(oldBase: old, root: base.appendingPathComponent("Koebumi"))

        #expect(new == base.appendingPathComponent("Koebumi/qwen3-speech", isDirectory: true))
        #expect(try new.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(fm.fileExists(atPath: LocalModelLocation.directory(of: .granite, in: new)
            .appendingPathComponent(LocalSpeechModel.readyMarkerName).path))
    }

    @Test func doesNothingWithoutAnOldFolder() throws {
        let base = try makeBase()
        defer { try? fm.removeItem(at: base) }
        #expect(LocalModelLocation.moveModels(from: base.appendingPathComponent("missing"), to: base.appendingPathComponent("new")).isEmpty)
    }
}
