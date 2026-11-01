import Foundation
import Testing
@testable import Koebumi

@Suite struct SpeechCppTests {
    @Test func samplesAreSentAsLittleEndian16BitBase64() {
        let data = Data(base64Encoded: SpeechCppModel.pcm16Base64([0, 1, -1, 2][...]))!
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }.map { Int16(littleEndian: $0) }
        // 範囲の外の値は -1〜1 に収める
        #expect(values == [0, 32767, -32767, 32767])
    }

    @Test func keywordsWithSeparatorsAreDropped() {
        // Haas の語彙は「表記=読み,読み」の形なので、区切りの文字を含む語は渡せない
        #expect(SpeechCppModel.sanitized([" Koebumi ", "a=b", "x,y", "", "Koebumi", "改\n行"]) == ["Koebumi"])
    }

    @Test func audioIsSentInChunksAndTheTextComesBack() throws {
        let model = try SpeechCppModel(executable: try FakeWorker.make(), modelFile: URL(fileURLWithPath: "/tmp/fake.gguf"))
        // 25 秒の音声は 10 秒ずつ 3 回に分けて送る
        let text = try model.transcribeAudio([Float](repeating: 0.1, count: 400_000), sampleRate: 16_000, keywords: ["Koebumi"])
        #expect(text == "chunks=3 keywords=yes")
        // 2 回目の依頼も同じワーカーが受ける
        #expect(try model.transcribeAudio([0.1, 0.2], sampleRate: 16_000) == "chunks=1 keywords=no")
        model.unload()
        #expect(!model.isLoaded)
        #expect(throws: SpeechCppError.self) { try model.transcribeAudio([0.1], sampleRate: 16_000) }
    }

    @Test func aWorkerThatCannotStartReportsItsReason() throws {
        #expect {
            _ = try SpeechCppModel(executable: try FakeWorker.make(fatal: true), modelFile: URL(fileURLWithPath: "/tmp/missing.gguf"))
        } throws: { error in
            guard case SpeechCppError.workerFailed(let message) = error else { return false }
            return message.contains("no such model file")
        }
    }

    @Test func emptyAudioIsNotSent() throws {
        let model = try SpeechCppModel(executable: try FakeWorker.make(), modelFile: URL(fileURLWithPath: "/tmp/fake.gguf"))
        #expect(try model.transcribeAudio([], sampleRate: 16_000) == "")
    }
}

/// speech worker の代わりに、ready を返し、届いた chunk の数と語彙の有無を文として返すスクリプト
private enum FakeWorker {
    static func make(fatal: Bool = false) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("koebumi-fake-speech-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("speech")
        let script = fatal ? """
        #!/bin/sh
        echo '{"type":"fatal","error":{"code":"model_file","option":null,"message":"no such model file"}}'
        exit 1
        """ : """
        #!/bin/sh
        echo '{"type":"ready","protocol":4,"version":"0.10.0","defaults":{},"model":{}}'
        chunks=0
        while IFS= read -r line; do
          case "$line" in
            *'"type":"chunk"'*) chunks=$((chunks + 1)) ;;
            *'"type":"transcribe"'*)
              id=$(printf '%s' "$line" | sed -E 's/.*"id":"([^"]*)".*/\\1/')
              case "$line" in *'"keywords"'*) kw=yes ;; *) kw=no ;; esac
              echo "{\\"type\\":\\"end\\",\\"id\\":\\"$id\\",\\"text\\":\\"chunks=$chunks keywords=$kw\\",\\"stop\\":\\"complete\\"}"
              chunks=0 ;;
          esac
        done
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
