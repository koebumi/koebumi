import AppKit
import SwiftUI

/// 音声認識のエンジンを選ぶ一覧（設定 > AI エンジン）。速さ・正確さ・大きさを並べて、その場でダウンロードして選べる。
struct SpeechEngineList<Detail: View>: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @ObservedObject var models = LocalModelStore.shared
    /// 選んだ行のすぐ下に出す設定（API キーなど）
    @ViewBuilder var detail: (SpeechEngineChoice) -> Detail

    private var selected: SpeechEngineChoice { SpeechEngineChoice(settingsStore.settings) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(t("音声認識", "Speech recognition"),
                         subtitle: t("この Mac で動かすモデルはキーが要らず、音声が Mac の外に出ません。", "Models on this Mac need no key, and audio never leaves your Mac."))
            SettingsGroup {
                ForEach(SpeechEngineChoice.onDevice) { rowWithDetail($0) }
            }
            SectionLabel(t("クラウドの音声認識", "Cloud speech recognition"),
                         subtitle: t("API キーが必要です。音声を選んだサービスに送ります。", "Needs an API key. Audio is sent to the service you choose."))
            SettingsGroup {
                ForEach(SpeechEngineChoice.cloud) { rowWithDetail($0) }
            }
        }
        .onAppear { models.refresh() }
    }

    @ViewBuilder
    private func rowWithDetail(_ choice: SpeechEngineChoice) -> some View {
        row(choice)
        if choice == selected { detail(choice) }
    }

    private func row(_ choice: SpeechEngineChoice) -> some View {
        SpeechEngineRow(choice: choice, isSelected: choice == selected, state: state(choice),
                        select: { select(choice) },
                        download: { if case .local(let m) = choice { models.download(m) } },
                        delete: { if case .local(let m) = choice { models.delete(m) } },
                        reveal: { if case .local(let m) = choice, let dir = m.cacheDirectory { NSWorkspace.shared.activateFileViewerSelecting([dir]) } })
    }

    private func state(_ choice: SpeechEngineChoice) -> LocalModelStore.State? {
        if case .local(let m) = choice { return models.state(m) }
        return nil
    }

    /// 選んだモデルがまだ無ければ、ダウンロードも始める
    private func select(_ choice: SpeechEngineChoice) {
        choice.apply(to: &settingsStore.settings)
        if case .local(let m) = choice, models.state(m) == .notDownloaded { models.download(m) }
    }
}

private struct SpeechEngineRow: View {
    let choice: SpeechEngineChoice
    let isSelected: Bool
    let state: LocalModelStore.State?
    let select: () -> Void
    let download: () -> Void
    let delete: () -> Void
    let reveal: () -> Void
    @State private var hovering = false

    private var info: SpeechEngineInfo { SpeechEngineInfo(choice) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RadioMark(isOn: isSelected)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(info.title)
                        .font(.ui(13.5, .medium))
                        .foregroundStyle(Palette.text)
                    if info.recommended { Badge(text: t("おすすめ", "Recommended"), tone: .accent) }
                }
                Text(info.summary)
                    .font(.ui(12.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if case .failed(let message) = state {
                    Text(message)
                        .font(.ui(12))
                        .foregroundStyle(Palette.danger)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 10) {
                        Text((info.details + [info.languageNote]).joined(separator: "  ·  "))
                            .foregroundStyle(Palette.textTertiary)
                        if state == .ready {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark").font(.system(size: 9.5, weight: .bold)).foregroundStyle(Palette.success)
                                Text(t("ダウンロード済み", "Downloaded")).foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                    .font(.ui(11.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let speed = info.speed, let accuracy = info.accuracy {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
                    GridRow {
                        Text(t("速さ", "Speed")).meterLabel()
                        RatingMeter(value: speed)
                    }
                    GridRow {
                        Text(t("正確さ", "Accuracy")).meterLabel()
                        RatingMeter(value: accuracy)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(t("速さ \(speed)、正確さ \(accuracy)（5 段階）", "Speed \(speed), accuracy \(accuracy) out of 5"))
            }
            // ボタンのない行でもメーターの位置をそろえる
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                trailing
            }
            .frame(width: 92)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(isSelected ? Palette.accent.opacity(0.06) : (hovering ? Palette.hover : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .none:
            if isSelected { Badge(text: t("使用中", "In use"), tone: .success, symbol: "checkmark") }
        case .notDownloaded:
            Button(t("ダウンロード", "Download"), action: download)
                .buttonStyle(.aside(compact: true))
        case .failed:
            Button(t("再試行", "Retry"), action: download)
                .buttonStyle(.aside(compact: true))
        case .downloading(let progress):
            VStack(alignment: .trailing, spacing: 5) {
                Text(progress > 0 ? "\(Int(progress * 100))%" : t("準備中…", "Starting…"))
                    .font(.ui(11.5, .medium).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                ProgressBar(value: progress)
                    .frame(width: 80)
            }
        case .ready:
            HStack(spacing: 6) {
                if isSelected { Badge(text: t("使用中", "In use"), tone: .success, symbol: "checkmark") }
                MenuButton(trailing: true, entries: {
                    [
                        .item(t("Finder で表示", "Show in Finder"), symbol: "folder", action: reveal),
                        .item(t("削除", "Delete"), symbol: "trash", destructive: true, action: delete),
                    ]
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(t("その他", "More"))
            }
        }
    }
}

/// 選択の丸
private struct RadioMark: View {
    var isOn: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(isOn ? Palette.accent : Palette.controlBorder, lineWidth: isOn ? 5 : 1.5)
        }
        .frame(width: 16, height: 16)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isOn)
    }
}

/// 5 段階の目盛り
private struct RatingMeter: View {
    var value: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Capsule()
                    .fill(i <= value ? Palette.accent : Palette.meter)
                    .frame(width: 9, height: 4)
            }
        }
    }
}

private extension Text {
    func meterLabel() -> some View {
        font(.ui(11)).foregroundStyle(Palette.textTertiary)
    }
}

/// 一覧の 1 行に出す内容
private struct SpeechEngineInfo {
    var title: String
    var summary: String
    var details: [String]
    var speed: Int?
    var accuracy: Int?
    var detectsLanguage = false
    var recommended = false

    var languageNote: String {
        detectsLanguage ? t("言語を自動判定", "Detects language") : t("言語は音声バーで選ぶ", "Language set on the voice bar")
    }

    init(_ choice: SpeechEngineChoice) {
        switch choice {
        case .apple:
            title = t("Apple の音声認識", "Apple speech recognition")
            summary = t("録音しながら文字にするので、話し終えてから約 0.5 秒で結果が出ます。言語は音声バーで選びます。",
                        "Transcribes while you record, so results appear about 0.5 s after you stop. Pick the language on the voice bar.")
            details = ["Apple", t("macOS に内蔵", "Built into macOS")]
            speed = 5
            accuracy = 3
        case .local(let m):
            title = m.title
            summary = m.summary
            details = [m.maker, m.sizeText, t("\(m.languageCount) 言語", "\(m.languageCount) languages")]
            speed = m.speed
            accuracy = m.accuracy
            detectsLanguage = m.detectsLanguage
            recommended = m.isRecommended
        case .cloud(let p):
            title = p == .custom ? t("カスタム（OpenAI 互換）", "Custom (OpenAI-compatible)") : p.title
            detectsLanguage = true
            switch p {
            case .openai:
                summary = t("OpenAI の gpt-4o-transcribe で認識します。", "Transcribes with OpenAI's gpt-4o-transcribe.")
                details = ["OpenAI", t("API キーが必要", "API key required")]
            case .groq:
                summary = t("Groq の上で Whisper Large v3 Turbo を動かします。", "Runs Whisper Large v3 Turbo on Groq.")
                details = ["Groq", t("API キーが必要", "API key required")]
            default:
                summary = t("OpenAI 互換の /audio/transcriptions に送ります。whisper.cpp などの自分のサーバーも使えます。",
                            "Sends audio to any OpenAI-compatible /audio/transcriptions endpoint, such as your own whisper.cpp server.")
                details = [t("URL を指定", "Your own URL")]
            }
        }
    }
}
