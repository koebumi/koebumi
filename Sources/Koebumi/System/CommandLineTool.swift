import Foundation

/// この Mac に入っているコマンド（claude・codex）を探して動かす。
/// Finder から起動したアプリの PATH には Homebrew や ~/.local/bin が入っていないため、よく入れられる場所とログインシェルの PATH から探す。
enum CommandLineTool {
    struct Output {
        var status: Int32
        var stdout: Data
        var stderr: Data
        var timedOut = false
    }

    private static let found = Locked<[String: URL]>([:])

    /// よく入れられる場所（公式インストーラー・Homebrew・npm・bun・volta）
    static func candidateDirectories(home: String = NSHomeDirectory()) -> [String] {
        [
            "\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin",
            "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/bin",
        ]
    }

    /// コマンドの場所。見つけた場所は覚えておき、消えていたら探し直す
    static func locate(_ name: String) -> URL? {
        let fm = FileManager.default
        if let url = found.value[name], fm.isExecutableFile(atPath: url.path) { return url }
        let path = candidateDirectories().map { "\($0)/\(name)" }.first { fm.isExecutableFile(atPath: $0) }
            ?? loginShellLookup(name)
        guard let path else { return nil }
        let url = URL(fileURLWithPath: path)
        found.withLock { $0[name] = url }
        return url
    }

    /// nvm などで入れた場所は、ログインシェルに聞く（シェルの設定ファイルが PATH を足す）
    private static func loginShellLookup(_ name: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v \(name)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // シェルの設定ファイルが止まっても待ち続けない
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate() }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { $0.hasPrefix("/") }
    }

    /// 子プロセスの環境変数。node で動くコマンド（npm の codex など）が node を見つけられるよう、PATH にコマンドの場所を足す
    static func environment(for executable: URL, removing: [String] = []) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in removing { env.removeValue(forKey: key) }
        var dirs = [executable.deletingLastPathComponent().path] + candidateDirectories()
        dirs += (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = dirs.filter { seen.insert($0).inserted }.joined(separator: ":")
        return env
    }

    /// コマンドを動かし、標準入力に input を渡して、終わるまで待つ。タスクを取り消すとコマンドも止める
    static func run(_ executable: URL, arguments: [String], input: String? = nil, directory: URL? = nil,
                    environment: [String: String]? = nil, timeout: TimeInterval = 60) async throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        process.environment = environment ?? Self.environment(for: executable)
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let handle = ProcessHandle(process)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
                // 出力が多くてもパイプが詰まらないよう、終わるのを待たずに読み続ける
                let out = Locked(Data()), err = Locked(Data())
                let reading = DispatchGroup()
                for (pipe, box) in [(stdout, out), (stderr, err)] {
                    reading.enter()
                    DispatchQueue.global().async {
                        box.value = pipe.fileHandleForReading.readDataToEndOfFile()
                        reading.leave()
                    }
                }
                process.terminationHandler = { p in
                    reading.notify(queue: .global()) {
                        continuation.resume(returning: Output(status: p.terminationStatus, stdout: out.value, stderr: err.value, timedOut: handle.timedOut))
                    }
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    try? stdout.fileHandleForWriting.close()
                    try? stderr.fileHandleForWriting.close()
                    continuation.resume(throwing: error)
                    return
                }
                if let input {
                    let writer = stdin.fileHandleForWriting
                    // 子プロセスが先に終わっても、書き込みで SIGPIPE を受けて Koebumi ごと落ちないようにする
                    _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
                    DispatchQueue.global().async {
                        try? writer.write(contentsOf: Data(input.utf8))
                        try? writer.close()
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { handle.stop(timedOut: true) }
            }
        } onCancel: {
            handle.stop(timedOut: false)
        }
    }
}

/// 別スレッドから止められるようにした Process
final class ProcessHandle: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()
    private var didTimeOut = false

    init(_ process: Process) { self.process = process }

    var timedOut: Bool { lock.withLock { didTimeOut } }

    func stop(timedOut: Bool) {
        lock.withLock {
            guard process.isRunning else { return }
            if timedOut { didTimeOut = true }
            process.terminate()
        }
    }
}

/// 複数のスレッドから読み書きする値
final class Locked<Value>: @unchecked Sendable {
    private var stored: Value
    private let lock = NSLock()

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func withLock<T>(_ body: (inout Value) -> T) -> T {
        lock.withLock { body(&stored) }
    }
}
