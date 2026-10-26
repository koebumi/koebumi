import AppKit

// `Koebumi --transcribe <音声ファイル>` / `Koebumi --polish <テキスト>` で、メニューバーアプリを起動せずに認識と整形だけを試せる。
if CommandLine.arguments.contains("--transcribe") || CommandLine.arguments.contains("--polish") {
    Task { @MainActor in
        let code = await CLI.run(CommandLine.arguments)
        exit(code)
    }
    dispatchMain()
}

// `Koebumi --dictionary list|add|remove|skill` で、エージェントが辞書を読み書きする（App/DictionaryCommand.swift）
if CommandLine.arguments.contains("--dictionary") {
    MainActor.assumeIsolated { exit(DictionaryCommand.run(CommandLine.arguments)) }
}

// 開発用: `Koebumi --eval <cases.json>` / `--read-context` / `--detect-agent` / `--context-demo <テキスト>` / `--answer-prompt <テキスト>`（App/Eval.swift）
if ["--eval", "--read-context", "--detect-agent", "--context-demo", "--stt-terms-test", "--answer-prompt"].contains(where: CommandLine.arguments.contains) {
    Task { @MainActor in exit(await Eval.run(CommandLine.arguments)) }
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
