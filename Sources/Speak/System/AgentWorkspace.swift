import Darwin
import Foundation

/// 入力先のエージェントと、その作業フォルダ・使えるスラッシュコマンド
struct AgentTarget: Equatable {
    var agents: [CodingAgent] = []
    /// この Mac の作業フォルダ（見つからなければ nil）。そのフォルダの .claude にある自作のコマンドを探す
    var directory: String?
    /// SSH 先で動いていれば、そのマシン。この Mac か SSH 先か分からないときは、両方のコマンドを使う
    var hosts: [RemoteHost] = []
    /// 声で入力できるスラッシュコマンド（「/」なし）
    var commands: [String] = []
    /// Claude Code が出している許可の確認。出ている間は、答える言葉だけを受け付ける
    var prompt: PermissionPrompt?
    /// herdr で選んでいる区画（許可の確認を読み直すときに、その区画だけを読む）
    var herdrPane: String?
    /// 作業フォルダのファイル。話したファイル名を、この表記に直す
    var files = ProjectFiles()
}

/// 前面の端末で、どのエージェントにどのフォルダで話しかけているかを調べる。録音と並行して呼ぶ
enum AgentWorkspace {
    static func locate(pid: pid_t, windowTitle: String?) -> AgentTarget {
        let start = Date()
        let target = find(pid: pid, windowTitle: windowTitle)
        // どの方法で何を取れたか（うまくいかなかったときに原因を追えるように。フォルダの名前や画面の文字は残さない）
        NSLog("Speak: agent=\(target.agents.map(\.name)) directory=\(target.directory != nil) hosts=\(target.hosts.count) "
              + "commands=\(target.commands.count) files=\(target.files.paths.count) prompt=\(target.prompt != nil) ms=\(Int(Date().timeIntervalSince(start) * 1000))")
        return target
    }

    private static func find(pid: pid_t, windowTitle: String?) -> AgentTarget {
        var target = AgentTarget()
        var local = true
        if let pane = Herdr.focusedPane(windowTitle: windowTitle) {
            // herdr はどの区画を選んでいるかを知っているので、画面の文字より確か（左右に分けたシェルの区画も見分けられる）
            target.agents = pane.agent.map { [$0] } ?? []
            if pane.agent == .claudeCode {
                target.herdrPane = pane.id
                target.prompt = permissionPrompt(pid: pid, windowTitle: windowTitle, herdrPane: pane.id)
            }
            if let remote = pane.remote {
                target.hosts = [RemoteHost(arguments: remote, directory: pane.directory)]
                local = false
            } else if pane.agent != nil {
                target.directory = pane.directory
            }
        } else {
            let screen = CodingAgent.readScreen(pid: pid)
            target.agents = screen.map(CodingAgent.detect) ?? []
            target.prompt = screen.flatMap(CodingAgent.permissionPrompt(in:))
            guard target.agents.count == 1 else { return target }
            if let machine = Herdr.remoteMachine(windowTitle) {
                // herdr が SSH 先の区画を答えなかった
                target.hosts = [RemoteHost(arguments: [machine])]
                local = false
            } else {
                // 端末から ssh でつないでいれば、SSH 先で動いているエージェントかもしれない
                let (sessions, agentHere) = terminalProcesses(pid, agent: target.agents[0])
                target.hosts = sessions.map { RemoteHost(arguments: $0) }
                local = sessions.isEmpty || agentHere
            }
            if local { target.directory = localDirectory(of: target.agents[0]) }
        }
        guard target.agents.count == 1 else { return target }
        let agent = target.agents[0]
        // SSH 先の自作のコマンドは ssh で読む（読めなければ組み込みのものだけ）
        var names = local ? commands(for: agent, directory: target.directory) : builtInCommands(for: agent)
        for host in target.hosts { names += remoteCommands(for: agent, on: host) ?? [] }
        target.commands = unique(names)
        // SSH 先のファイルは、コマンドと同じ接続で読んだもの
        if local, let directory = target.directory { target.files = ProjectFiles.read(directory: directory) }
        for host in target.hosts where target.files.paths.isEmpty { target.files = RemoteFiles.read(host)?.projectFiles ?? ProjectFiles() }
        return target
    }

    /// 前面の端末に出ている許可の確認。herdr では選んでいる区画だけを読む（隣の区画の確認に答えないように）
    static func permissionPrompt(pid: pid_t, windowTitle: String?, herdrPane: String?) -> PermissionPrompt? {
        if let herdrPane {
            // 区画だけを読むので、画面を区画に分けたり、確認がいちばん下にあるかを見たりしない
            return Herdr.visibleText(of: herdrPane, windowTitle: windowTitle)
                .flatMap { CodingAgent.permissionPrompt(in: $0.components(separatedBy: "\n"), atBottom: false) }
        }
        return CodingAgent.readScreen(pid: pid).flatMap(CodingAgent.permissionPrompt(in:))
    }

    static func unique<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        return items.filter { seen.insert($0).inserted }
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

    /// 組み込みのコマンドと、自分で作ったコマンド（Claude Code は skills と commands、Codex は prompts）。
    /// files を SSH 先のものにすれば、SSH 先で探す
    static func commands(for agent: CodingAgent, directory: String?, in files: any CommandFiles = LocalFiles()) -> [String] {
        var names = builtInCommands(for: agent)
        switch agent {
        case .claudeCode:
            for base in [files.home + "/.claude"] + (directory.map { [$0 + "/.claude"] } ?? []) {
                names += files.folders(in: base + "/skills") + files.files(in: base + "/commands", extension: "md")
            }
            names += pluginCommands(files)
        case .codex:
            names += files.files(in: files.home + "/.codex/prompts", extension: "md").map { "prompts:" + $0 }
        }
        return unique(names)
    }

    /// SSH 先のコマンド。ssh でつなげなければ nil
    static func remoteCommands(for agent: CodingAgent, on host: RemoteHost) -> [String]? {
        RemoteFiles.read(host).map { commands(for: agent, directory: $0.directory, in: $0) }
    }

    /// プラグインのスキルとコマンド（「プラグイン名:スキル名」で呼ぶ）
    private static func pluginCommands(_ files: any CommandFiles) -> [String] {
        struct Installed: Decodable {
            struct Install: Decodable { var installPath: String }
            var plugins: [String: [Install]]
        }
        guard let data = files.read(files.home + "/.claude/plugins/installed_plugins.json"),
              let installed = try? JSONDecoder().decode(Installed.self, from: data)
        else { return [] }
        return installed.plugins.sorted { $0.key < $1.key }.flatMap { key, installs -> [String] in
            guard let path = installs.first?.installPath, let plugin = key.split(separator: "@").first else { return [] }
            let names = files.folders(in: path + "/skills") + files.files(in: path + "/commands", extension: "md")
            return names.map { "\(plugin):\($0)" }
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

    /// 端末アプリから起動したプロセスのうち、対話で使っている ssh の接続先と、この Mac でエージェントが動いているか。
    /// herdr や tmux の中で動くものは端末アプリの子ではないので、ここでは見つからない
    private static func terminalProcesses(_ terminal: pid_t, agent: CodingAgent) -> (ssh: [[String]], agentHere: Bool) {
        let parents = parentProcesses()
        func launched(_ pid: pid_t) -> Bool {
            var p = pid
            for _ in 0..<32 {
                guard let parent = parents[p], parent > 1 else { return false }
                if parent == terminal { return true }
                p = parent
            }
            return false
        }
        let arguments = parents.keys.filter(launched).map(arguments(of:))
        return (unique(arguments.compactMap(SSH.connection)), arguments.contains { isInteractive(agent, arguments: $0) })
    }

    /// すべてのプロセスと、その親（proc_pidinfo では root で動く login の親を読めないので、sysctl で読む）
    private static func parentProcesses() -> [pid_t: pid_t] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [:] }
        // 読むまでのあいだに増えたプロセスのぶん、少し多めに取る
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 32)
        size = procs.count * MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [:] }
        return Dictionary(procs.prefix(size / MemoryLayout<kinfo_proc>.stride).map { ($0.kp_proc.p_pid, $0.kp_eproc.e_ppid) },
                          uniquingKeysWith: { a, _ in a })
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

/// スラッシュコマンドを探すファイルの読み方（この Mac か、ssh で読んだ SSH 先）
protocol CommandFiles {
    var home: String { get }
    /// フォルダの中身。フォルダは名前の最後に「/」を付ける
    func list(_ path: String) -> [String]
    func read(_ path: String) -> Data?
}

extension CommandFiles {
    func folders(in path: String) -> [String] {
        list(path).filter { $0.hasSuffix("/") && !$0.hasPrefix(".") }.map { String($0.dropLast()) }
    }

    func files(in path: String, extension ext: String) -> [String] {
        list(path).filter { !$0.hasSuffix("/") && !$0.hasPrefix(".") && ($0 as NSString).pathExtension == ext }
            .map { ($0 as NSString).deletingPathExtension }
    }
}

struct LocalFiles: CommandFiles {
    var home: String { NSHomeDirectory() }

    func list(_ path: String) -> [String] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: path)) ?? []).map { name in
            var isDirectory: ObjCBool = false
            return fm.fileExists(atPath: path + "/" + name, isDirectory: &isDirectory) && isDirectory.boolValue ? name + "/" : name
        }
    }

    func read(_ path: String) -> Data? { FileManager.default.contents(atPath: path) }
}

/// herdr（AI エージェント向けの端末の分割ツール）に、選んでいる区画を聞く
enum Herdr {
    struct Pane: Equatable {
        var id = ""
        var agent: CodingAgent?
        /// 作業フォルダ（SSH 先のマシンの区画なら、SSH 先のパス）
        var directory: String?
        /// SSH 先で動いていれば、ssh に渡す接続先
        var remote: [String]?
    }

    private static let candidates = ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr", NSHomeDirectory() + "/.local/bin/herdr",
                                     NSHomeDirectory() + "/.cargo/bin/herdr"]
    private static var binary: String? { candidates.first(where: FileManager.default.isExecutableFile(atPath:)) }

    /// herdr のウィンドウなら、選んでいる区画。SSH 先のマシンを開いていれば、そのマシンの herdr に聞く
    static func focusedPane(windowTitle: String?) -> Pane? {
        guard let windowTitle, let binary, let machine = splitTitle(windowTitle)?.machine else { return nil }
        let host = ProcessInfo.processInfo.hostName
        if isThisMac(machine, hostName: host) {
            guard let data = Subprocess.run(binary, ["api", "snapshot"], timeout: 0.5),
                  var pane = parse(data, windowTitle: windowTitle, hostName: host)
            else { return nil }
            // 区画で ssh を動かしていると、SSH 先で動くエージェントを herdr は見分けない。区画の文字で見分ける
            if pane.agent == nil, let info = Subprocess.run(binary, ["pane", "process-info", "--pane", pane.id], timeout: 0.5),
               let ssh = sshConnection(info),
               let screen = Subprocess.run(binary, ["pane", "read", pane.id, "--source", "visible"], timeout: 0.5),
               case let agents = CodingAgent.detect(in: String(decoding: screen, as: UTF8.self)), agents.count == 1 {
                pane = Pane(id: pane.id, agent: agents[0], remote: ssh)
            }
            return pane
        }
        guard let target = machines()?[machine] else { return nil }
        if let data = Subprocess.run(binary, ["--machine", machine, "api", "snapshot"], timeout: 2),
           var pane = parse(data, windowTitle: windowTitle, hostName: machine) {
            pane.remote = [target]
            lock.withLock { paneCache[windowTitle] = (Date(), pane) }
            return pane
        }
        // SSH 先の herdr がときどき答えないので、同じウィンドウで 30 秒以内に取れた区画を使う
        if let hit = lock.withLock({ paneCache[windowTitle] }), Date().timeIntervalSince(hit.date) < 30 { return hit.pane }
        return nil
    }

    /// 区画に表示している文字列。SSH 先のマシンを開いていれば、そのマシンの herdr に聞く
    static func visibleText(of pane: String, windowTitle: String?) -> String? {
        guard let windowTitle, let binary, let machine = splitTitle(windowTitle)?.machine else { return nil }
        let remote = isThisMac(machine, hostName: ProcessInfo.processInfo.hostName) ? [] : ["--machine", machine]
        let data = Subprocess.run(binary, remote + ["pane", "read", pane, "--source", "visible"], timeout: remote.isEmpty ? 0.5 : 2)
        return data.map { String(decoding: $0, as: UTF8.self) }
    }

    /// herdr で SSH 先のマシンを開いているウィンドウなら、その接続先。herdr にマシンの一覧を聞けないときも、
    /// タイトルのマシン名がこの Mac でなく、マシン名らしい（空白や「/」「~」がない）ものなら、その名前で ssh につなぐ
    static func remoteMachine(_ windowTitle: String?) -> String? {
        guard let windowTitle, binary != nil, let machine = splitTitle(windowTitle)?.machine,
              !isThisMac(machine, hostName: ProcessInfo.processInfo.hostName)
        else { return nil }
        if let machines = machines() { return machines[machine] }
        return !machine.isEmpty && !machine.contains(where: { $0.isWhitespace || "/~".contains($0) }) ? machine : nil
    }

    /// herdr pane process-info の出力から、区画の前面で動いている ssh の接続先
    static func sshConnection(_ data: Data) -> [String]? {
        struct Response: Decodable {
            var result: Result
            struct Result: Decodable { var process_info: Info }
            struct Info: Decodable { var foreground_processes: [Foreground] }
            struct Foreground: Decodable { var argv: [String] }
        }
        let processes = (try? JSONDecoder().decode(Response.self, from: data))?.result.process_info.foreground_processes ?? []
        return processes.lazy.compactMap { SSH.connection($0.argv) }.first
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
        return Pane(id: pane.pane_id, agent: agent, directory: pane.foreground_cwd ?? pane.cwd)
    }
}

enum Subprocess {
    /// コマンドを実行して標準出力を返す。input は標準入力に渡す。失敗したときや、時間内に終わらなかったときは nil
    static func run(_ path: String, _ arguments: [String], input: Data? = nil, timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let stdin = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        do { try process.run() } catch { return nil }
        if let input {
            // 先に終わったコマンドに書き込んでも、SIGPIPE でアプリが落ちないようにする
            _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            try? stdin.fileHandleForWriting.write(contentsOf: input)
            try? stdin.fileHandleForWriting.close()
        }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return process.terminationReason == .exit && process.terminationStatus == 0 ? data : nil
    }
}
