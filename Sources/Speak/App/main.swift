import AppKit

// `Speak --transcribe <音声ファイル>` / `Speak --polish <テキスト>` で、メニューバーアプリを起動せずに認識と整形だけを試せる。
if CommandLine.arguments.contains("--transcribe") || CommandLine.arguments.contains("--polish") {
    Task { @MainActor in
        let code = await CLI.run(CommandLine.arguments)
        exit(code)
    }
    dispatchMain()
}

if CommandLine.arguments.contains("--snapshot") {
    MainActor.assumeIsolated {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task { @MainActor in exit(await Snapshot.run(CommandLine.arguments)) }
        NSApplication.shared.run()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
