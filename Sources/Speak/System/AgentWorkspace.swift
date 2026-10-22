import Darwin
import Foundation

/// 入力先のエージェントと、その作業フォルダ・使えるスラッシュコマンド
struct AgentTarget: Equatable {
    var agents: [CodingAgent] = []
    /// 作業フォルダ（この Mac で見つからなければ nil）。そのフォルダの .claude にある自作のコマンドを探す
    var directory: String?
    /// 声で入力できるスラッシュコマンド（「/」なし）
    var commands: [String] = []
}

/// 前面の端末で、どのエージェントにどのフォルダで話しかけているかを調べる。録音と並行して呼ぶ
enum AgentWorkspace {
    static func locate(pid: pid_t, windowTitle: String?) -> AgentTarget {
        let start = Date()
        let target = find(pid: pid, windowTitle: windowTitle)
        // どの方法で何を取れたか（うまくいかなかったときに原因を追えるように。フォルダの名前や画面の文字は残さない）
        NSLog("Speak: agent=\(target.agents.map(\.name)) directory=\(target.directory != nil) commands=\(target.commands.count) "
              + "ms=\(Int(Date().timeIntervalSince(start) * 1000))")
        return target
    }

    private static func find(pid: pid_t, windowTitle: String?) -> AgentTarget {
        var target = AgentTarget()
        var remote = Herdr.showsRemoteMachine(windowTitle)
        if let pane = Herdr.focusedPane(windowTitle: windowTitle) {
            // herdr はどの区画を選んでいるかを知っているので、画面の文字より確か（左右に分けたシェルの区画も見分けられる）
            target.agents = pane.agent.map { [$0] } ?? []
            remote = pane.machine != nil
            if pane.agent != nil, !remote { target.directory = pane.directory }
        } else {
            target.agents = CodingAgent.readScreen(pid: pid).map(CodingAgent.detect) ?? []
            // SSH 先のマシンを開いた herdr のウィンドウでは、この Mac で動いているエージェントのフォルダを使わない
            if target.agents.count == 1, !remote { target.directory = localDirectory(of: target.agents[0]) }
        }
        guard target.agents.count == 1 else { return target }
        // SSH 先の自作のコマンドはこの Mac にないので、組み込みのものだけ
        target.commands = remote ? builtInCommands(for: target.agents[0]) : commands(for: target.agents[0], directory: target.directory)
        return target
    }

    static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    // MARK: - スラッシュコマンド

    static func builtInCommands(for agent: CodingAgent) -> [String] {
        switch agent {
        case .claudeCode:
            // Claude Code 2.1 の実行ファイルにあるコマンドのうち、人が使うもの
            return ["add-dir", "agents", "branch", "btw", "clear", "color", "compact", "config", "context", "copy", "diff", "doctor",
                    "effort", "exit", "export", "fast", "feedback", "fork", "goal", "help", "hooks", "ide", "init", "insights",
                    "keybindings", "login", "logout", "loops", "mcp", "memory", "model", "permissions", "plan", "plugin", "recap",
                    "reload-plugins", "reload-skills", "rename", "restart", "resume", "rewind", "security-review", "session", "skills",
                    "status", "statusline", "stop", "tasks", "terminal-setup", "theme", "todos", "ultraplan", "ultrareview", "usage",
                    "voice", "workflows",
                    // 最初から入っているスキル
                    "simplify", "loop", "schedule", "run", "claude-api", "update-config", "keybindings-help", "fewer-permission-prompts"]
        case .codex:
            return ["approvals", "clear", "compact", "diff", "exit", "feedback", "fork", "init", "logout", "mcp", "mention", "model",
                    "new", "permissions", "plan", "quit", "rename", "resume", "review", "skills", "status", "theme"]
        }
    }

    /// 組み込みのコマンドと、自分で作ったコマンド（Claude Code は skills と commands、Codex は prompts）
    static func commands(for agent: CodingAgent, directory: String?) -> [String] {
        let home = NSHomeDirectory()
        var names = builtInCommands(for: agent)
        switch agent {
        case .claudeCode:
            for base in [home + "/.claude"] + (directory.map { [$0 + "/.claude"] } ?? []) {
                names += entries(in: base + "/skills", directories: true) + entries(in: base + "/commands", extension: "md")
            }
            names += pluginCommands(home: home)
        case .codex:
            names += entries(in: home + "/.codex/prompts", extension: "md").map { "prompts:" + $0 }
        }
        return unique(names)
    }

    /// プラグインのスキルとコマンド（「プラグイン名:スキル名」で呼ぶ）
    private static func pluginCommands(home: String) -> [String] {
        struct Installed: Decodable {
            struct Install: Decodable { var installPath: String }
            var plugins: [String: [Install]]
        }
        guard let data = FileManager.default.contents(atPath: home + "/.claude/plugins/installed_plugins.json"),
              let installed = try? JSONDecoder().decode(Installed.self, from: data)
        else { return [] }
        return installed.plugins.sorted { $0.key < $1.key }.flatMap { key, installs -> [String] in
            guard let path = installs.first?.installPath, let plugin = key.split(separator: "@").first else { return [] }
            let names = entries(in: path + "/skills", directories: true) + entries(in: path + "/commands", extension: "md")
            return names.map { "\(plugin):\($0)" }
        }
    }

    private static func entries(in directory: String, directories: Bool = false, extension ext: String? = nil) -> [String] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return [] }
        return names.filter { !$0.hasPrefix(".") }.compactMap { name in
            if directories {
                var isDirectory: ObjCBool = false
                return fm.fileExists(atPath: directory + "/" + name, isDirectory: &isDirectory) && isDirectory.boolValue ? name : nil
            }
            return (name as NSString).pathExtension == ext ? (name as NSString).deletingPathExtension : nil
        }
    }

    // MARK: - プロセス

    /// この Mac で動いているエージェントのプロセスがみな同じフォルダにいれば、そのフォルダ。
    /// 別々のフォルダで複数動いていると、どれに話しかけているかわからないので nil
    static func localDirectory(of agent: CodingAgent) -> String? {
        let directories = Set(allProcesses().filter { isInteractive(agent, arguments: arguments(of: $0)) }.compactMap(currentDirectory))
        return directories.count == 1 ? directories.first : nil
    }

    /// 起動したときの名前で見分ける（Claude Code の実行ファイル名は版の番号なので、プロセス名では探せない）。
    /// Codex が裏で動かすサーバー（codex app-server など）は、話しかける相手ではないので除く
    static func isInteractive(_ agent: CodingAgent, arguments: [String]) -> Bool {
        guard let first = arguments.first else { return false }
        let name = (first as NSString).lastPathComponent
        switch agent {
        case .claudeCode:
            return name == "claude" && !["mcp", "doctor", "update", "install"].contains(arguments[safe: 1] ?? "")
        case .codex:
            return name == "codex" && !["app-server", "mcp", "mcp-server", "exec", "login", "logout", "proto"].contains(arguments[safe: 1] ?? "")
        }
    }

    private static func allProcesses() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return pids.prefix(Int(max(filled, 0))).filter { $0 > 0 }
    }

    /// プロセスを起動したときの引数（argv）。自分のものでないプロセスは読めないので空
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        // 先頭に引数の数、その後に実行ファイルのパスと、0 で区切った引数が並ぶ
        let argc = Int(buffer.withUnsafeBytes { $0.load(as: Int32.self) })
        var i = MemoryLayout<Int32>.size
        while i < size, buffer[i] != 0 { i += 1 }
        while i < size, buffer[i] == 0 { i += 1 }
        var args: [String] = []
        while args.count < argc, i < size {
            let start = i
            while i < size, buffer[i] != 0 { i += 1 }
            args.append(String(decoding: buffer[start..<i], as: UTF8.self))
            i += 1
        }
        return args
    }

    private static func currentDirectory(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
        return path.isEmpty ? nil : path
    }
}

/// herdr（AI エージェント向けの端末の分割ツール）に、選んでいる区画を聞く
enum Herdr {
    struct Pane: Equatable {
        var agent: CodingAgent?
        var directory: String?
        /// SSH 先のマシンの区画なら、その接続先
        var machine: String?
    }

    private static let candidates = ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr", NSHomeDirectory() + "/.local/bin/herdr",
                                     NSHomeDirectory() + "/.cargo/bin/herdr"]
    private static var binary: String? { candidates.first(where: FileManager.default.isExecutableFile(atPath:)) }

    /// herdr のウィンドウなら、選んでいる区画。SSH 先のマシンを開いていれば、そのマシンの herdr に聞く
    static func focusedPane(windowTitle: String?) -> Pane? {
        guard let windowTitle, let binary, let machine = splitTitle(windowTitle)?.machine else { return nil }
        let host = ProcessInfo.processInfo.hostName
        if isThisMac(machine, hostName: host) {
            guard let data = Subprocess.run(binary, ["api", "snapshot"], timeout: 0.5) else { return nil }
            return parse(data, windowTitle: windowTitle, hostName: host)
        }
        guard let target = machines()?[machine] else { return nil }
        if let data = Subprocess.run(binary, ["--machine", machine, "api", "snapshot"], timeout: 2),
           var pane = parse(data, windowTitle: windowTitle, hostName: machine) {
            pane.machine = target
            lock.withLock { paneCache[windowTitle] = (Date(), pane) }
            return pane
        }
        // SSH 先の herdr がときどき答えないので、同じウィンドウで 30 秒以内に取れた区画を使う
        if let hit = lock.withLock({ paneCache[windowTitle] }), Date().timeIntervalSince(hit.date) < 30 { return hit.pane }
        return nil
    }

    /// herdr で SSH 先のマシンを開いているウィンドウか。herdr にマシンの一覧を聞けないときも、
    /// タイトルのマシン名がこの Mac でなく、マシン名らしい（空白や「/」「~」がない）ものなら SSH 先とみなす
    static func showsRemoteMachine(_ windowTitle: String?) -> Bool {
        guard let windowTitle, binary != nil, let machine = splitTitle(windowTitle)?.machine,
              !isThisMac(machine, hostName: ProcessInfo.processInfo.hostName)
        else { return false }
        if let machines = machines() { return machines[machine] != nil }
        return !machine.isEmpty && !machine.contains(where: { $0.isWhitespace || "/~".contains($0) })
    }

    /// 「マシン名: ワークスペース名」
    static func splitTitle(_ title: String) -> (machine: String, workspace: String)? {
        guard let r = title.range(of: ": ") else { return nil }
        return (String(title[..<r.lowerBound]), String(title[r.upperBound...]))
    }

    private static func isThisMac(_ machine: String, hostName: String) -> Bool {
        let host = hostName.lowercased()
        return [host, host.replacingOccurrences(of: ".local", with: "")].contains(machine.lowercased())
    }

    private static let lock = NSLock()
    private static var machineCache: (date: Date, machines: [String: String])?
    private static var paneCache: [String: (date: Date, pane: Pane)] = [:]

    /// herdr に登録した SSH 先のマシン（名前 → 接続先）。1 分のあいだ覚えておき、聞けなかったときは前に聞いたものを使う。
    /// 一度も聞けていなければ nil
    private static func machines() -> [String: String]? {
        let cached = lock.withLock { machineCache }
        if let cached, Date().timeIntervalSince(cached.date) < 60 { return cached.machines }
        guard let binary, let data = Subprocess.run(binary, ["machine", "list"], timeout: 1) else { return cached?.machines }
        let machines = parseMachines(String(decoding: data, as: UTF8.self))
        lock.withLock { machineCache = (Date(), machines) }
        return machines
    }

    /// herdr machine list の出力（ID・名前・接続先・プロファイル・状態をタブで区切った行）
    static func parseMachines(_ text: String) -> [String: String] {
        var machines: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\t").map(String.init)
            guard fields.count >= 5, fields[4] == "enabled" else { continue }
            machines[fields[1]] = fields[2]
        }
        return machines
    }

    private struct Response: Decodable {
        var result: Result
        struct Result: Decodable { var snapshot: Snapshot }
        struct Snapshot: Decodable {
            var focused_workspace_id: String?
            var focused_pane_id: String?
            var workspaces: [Workspace]
            var panes: [PaneInfo]
        }
        struct Workspace: Decodable {
            var workspace_id: String
            var label: String?
        }
        struct PaneInfo: Decodable {
            var pane_id: String
            var agent: String?
            var cwd: String?
            var foreground_cwd: String?
        }
    }

    /// herdr のウィンドウのタイトルは「マシン名: ワークスペース名」。この Mac のワークスペースを開いているときだけ答える
    /// （SSH 先のマシンを開いていると、この Mac の herdr が選んでいる区画は画面に出ていない）
    static func parse(_ data: Data, windowTitle: String, hostName: String) -> Pane? {
        guard let s = try? JSONDecoder().decode(Response.self, from: data).result.snapshot,
              let label = s.workspaces.first(where: { $0.workspace_id == s.focused_workspace_id })?.label,
              let pane = s.panes.first(where: { $0.pane_id == s.focused_pane_id })
        else { return nil }
        let host = hostName.lowercased()
        let titles = [host, host.replacingOccurrences(of: ".local", with: "")].map { "\($0): \(label.lowercased())" }
        guard titles.contains(windowTitle.lowercased()) else { return nil }
        let agent: CodingAgent? = switch pane.agent {
        case "claude": .claudeCode
        case "codex": .codex
        default: nil
        }
        return Pane(agent: agent, directory: pane.foreground_cwd ?? pane.cwd)
    }
}

enum Subprocess {
    /// コマンドを実行して標準出力を返す。失敗したときや、時間内に終わらなかったときは nil
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return process.terminationReason == .exit && process.terminationStatus == 0 ? data : nil
    }
}
