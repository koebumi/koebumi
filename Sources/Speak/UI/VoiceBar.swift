import AppKit
import Combine
import SwiftUI

/// フォーカスを奪わないフローティングパネル。入力先アプリのカーソルを保ったままボタンを押せる。
final class FloatingPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum ScreenPlacement {
    /// マウスがある画面（なければメイン画面）
    static var activeScreen: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// 画面下中央にパネルを出す。SwiftUI の文字レイアウトが終わってから大きさが確定するので、少し後にもう一度合わせる。
    @MainActor
    static func show(_ panel: NSPanel, hosting: NSView, bottomOffset: CGFloat, while shouldShow: @escaping @MainActor () -> Bool) {
        let screen = activeScreen
        func place() {
            hosting.layoutSubtreeIfNeeded()
            let size = hosting.fittingSize
            guard let frame = screen?.visibleFrame, size.width > 0 else { return }
            let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + bottomOffset)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }
        DispatchQueue.main.async {
            guard shouldShow() else { return }
            place()
            panel.orderFrontRegardless()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if panel.isVisible, shouldShow() { place() }
        }
    }
}

// MARK: - 音声バー

@MainActor
final class VoiceBarController {
    private let panel = FloatingPanel()
    private let hosting: FirstMouseHostingView<VoiceBarView>
    private let controller: DictationController
    private var cancellables: Set<AnyCancellable> = []

    init(controller: DictationController) {
        self.controller = controller
        hosting = FirstMouseHostingView(rootView: VoiceBarView(controller: controller, settings: SettingsStore.shared))
        panel.contentView = hosting
        controller.$phase.combineLatest(controller.$mode)
            .receive(on: RunLoop.main)
            .sink { [weak self] phase, _ in self?.update(phase: phase) }
            .store(in: &cancellables)
    }

    private func update(phase: DictationController.Phase) {
        if phase == .idle {
            panel.orderOut(nil)
            return
        }
        ScreenPlacement.show(panel, hosting: hosting, bottomOffset: 28) { [controller] in controller.phase != .idle }
    }
}

struct VoiceBarView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: SettingsStore

    var body: some View {
        HStack(spacing: 10) {
            switch controller.phase {
            case .recording:
                modeBadge
                Waveform(levels: controller.levels, color: controller.mode.tint)
                    .frame(width: 104, height: 22)
                languageChip
                Text(timeString(controller.elapsed))
                    .font(.ui(11.5, .medium).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                    .frame(minWidth: 30)
                Rectangle().fill(Palette.divider).frame(width: 1, height: 18)
                barButton("xmark", help: t("キャンセル（Esc）", "Cancel (Esc)")) { controller.cancel() }
                barButton("checkmark", help: t("完了", "Done"), prominent: true) { controller.finish() }
            case .processing:
                Spinner(tint: controller.mode.tint)
                    .frame(width: 26, height: 26)
                ShimmerText(text: processingLabel)
                    .padding(.trailing, 2)
                barButton("xmark", help: t("キャンセル（Esc）", "Cancel (Esc)")) { controller.cancel() }
            case .message(let text, let isError):
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isError ? Palette.warning : Palette.success)
                    .padding(.leading, 6)
                Text(text)
                    .font(.ui(12.5, .medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(3)
                    .frame(maxWidth: 420, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 8)
            case .idle:
                EmptyView()
            }
        }
        .padding(7)
        .frame(minHeight: 42)
        .background(Capsule().fill(Palette.panel))
        .overlay(Capsule().strokeBorder(Palette.panelBorder))
        .fixedSize()
    }

    private var modeBadge: some View {
        Image(systemName: controller.mode.symbol)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(controller.mode.tint)
            .frame(width: 26, height: 26)
            .background(Circle().fill(controller.mode.tint.opacity(0.13)))
    }

    private var processingLabel: String {
        switch controller.mode {
        case .dictate: return t("整えています…", "Polishing…")
        case .translate: return t("翻訳しています…", "Translating…")
        case .ask: return t("考えています…", "Thinking…")
        }
    }

    @ViewBuilder
    private var languageChip: some View {
        let s = settings.settings
        if controller.mode == .translate {
            MenuButton(entries: {
                s.translationTargets.map { lang in
                    .item(Languages.name(lang), checked: lang == s.currentTranslationTarget) { controller.changeTranslationTarget(lang) }
                }
            }) {
                chipLabel(Languages.name(s.currentTranslationTarget), symbol: "arrow.right")
            }
            .buttonStyle(.plain)
        } else if s.dictationLanguages.count > 1 && s.sttProvider == .apple {
            MenuButton(entries: {
                s.dictationLanguages.map { lang in
                    .item(Languages.name(lang), checked: lang == s.currentDictationLanguage) { controller.changeDictationLanguage(lang) }
                }
            }) {
                chipLabel(Languages.name(s.currentDictationLanguage), symbol: nil)
            }
            .buttonStyle(.plain)
        }
    }

    private func chipLabel(_ text: String, symbol: String?) -> some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(controller.mode.tint) }
            Text(text).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 7.5, weight: .bold)).foregroundStyle(Palette.textTertiary)
        }
        .font(.ui(11.5, .medium))
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(Palette.hover))
        .overlay(Capsule().strokeBorder(Palette.cardBorder))
        .contentShape(Capsule())
    }

    private func barButton(_ symbol: String, help: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(prominent ? Palette.inverse : Palette.hover))
                .foregroundStyle(prominent ? Palette.inverseText : Palette.textSecondary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct Waveform: View {
    var levels: [Float]
    var color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(levels.indices, id: \.self) { i in
                let level = CGFloat(levels[i])
                Capsule()
                    .fill(color.opacity(0.45 + 0.55 * Double(min(level * 1.4, 1))))
                    .frame(width: 2.5, height: max(3, level * 22))
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
    }
}

/// 回る弧（処理中）
private struct Spinner: View {
    var tint: Color
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.13))
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(spinning ? 360 : 0))
        }
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spinning = true }
        }
    }
}

/// 光が左から右へ流れる文字
private struct ShimmerText: View {
    var text: String
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(.ui(12.5, .medium))
            .foregroundStyle(Palette.textSecondary)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, Palette.text, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.3)
                }
                .mask(Text(text).font(.ui(12.5, .medium)))
                .allowsHitTesting(false)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

// MARK: - 回答カード（Ask anything）

@MainActor
final class AnswerCardController {
    private let panel = FloatingPanel()
    private var cancellables: Set<AnyCancellable> = []

    init(controller: DictationController) {
        let hosting = FirstMouseHostingView(rootView: AnswerCardView(controller: controller))
        panel.contentView = hosting
        controller.$answer
            .receive(on: RunLoop.main)
            .sink { [weak self] content in
                guard let self else { return }
                guard content != nil else {
                    panel.orderOut(nil)
                    return
                }
                ScreenPlacement.show(panel, hosting: hosting, bottomOffset: 84) { [controller] in controller.answer != nil }
            }
            .store(in: &cancellables)
    }
}

struct AnswerCardView: View {
    @ObservedObject var controller: DictationController
    @State private var copied = false

    var body: some View {
        if let content = controller.answer {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    IconTile(symbol: "sparkles", tint: Palette.violet, size: 24)
                    Text("Ask anything")
                        .font(.ui(13, .medium))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    KeyCap(text: "Esc", compact: true)
                    IconButton(symbol: "xmark", help: t("閉じる（Esc）", "Close (Esc)"), size: 24) {
                        controller.answer = nil
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "quote.opening").font(.system(size: 9, weight: .bold))
                    Text(content.question).lineLimit(2)
                }
                .font(.ui(12.5))
                .foregroundStyle(Palette.textSecondary)
                .padding(.top, 14)
                Rectangle().fill(Palette.divider).frame(height: 1).padding(.vertical, 12)
                ScrollView {
                    Text(markdown(content.answer))
                        .font(.ui(13.5))
                        .foregroundStyle(Palette.text)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(height: min(answerHeight(content.answer), 320))
                HStack(spacing: 8) {
                    Spacer()
                    Button {
                        TextInserter.copyToClipboard(content.answer)
                        copied = true
                    } label: {
                        Label(copied ? t("コピーしました", "Copied") : t("コピー", "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.aside(compact: true))
                    Button {
                        let text = content.answer
                        controller.answer = nil
                        Task { await TextInserter.paste(text, keepInClipboard: false) }
                    } label: {
                        Label(t("カーソル位置に入力", "Insert at cursor"), systemImage: "text.insert")
                    }
                    .buttonStyle(.aside(.primary, compact: true))
                }
                .padding(.top, 14)
            }
            .padding(16)
            .frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.panelBorder))
            .onChange(of: content) { copied = false }
        }
    }

    /// ScrollView は中身の高さを親に伝えないため、本文の高さを先に計算して枠の高さにする
    private func answerHeight(_ text: String) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        let rect = (text as NSString).boundingRect(
            with: NSSize(width: 428, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 13.5), .paragraphStyle: style]
        )
        return ceil(rect.height) + 8
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
