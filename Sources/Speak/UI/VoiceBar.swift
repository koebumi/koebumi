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
            if !panel.isVisible { panel.alphaValue = 0 }
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if panel.isVisible, shouldShow() { place() }
        }
    }

    /// フェードしてから隠す。消えている途中で show されたら（alphaValue が 1 に戻っていたら）隠さない。
    @MainActor
    static func hide(_ panel: NSPanel) {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        }, completionHandler: {
            if panel.alphaValue == 0 { panel.orderOut(nil) }
        })
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
            ScreenPlacement.hide(panel)
            return
        }
        ScreenPlacement.show(panel, hosting: hosting, bottomOffset: 28) { [controller] in controller.phase != .idle }
    }
}

struct VoiceBarView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: SettingsStore

    /// 波形に出す本数。新しい音ほど右に出て、古い音は左端で薄く消える。
    private static let waveformBars = 20

    var body: some View {
        HStack(spacing: 8) {
            switch controller.phase {
            case .recording:
                modeBadge
                Waveform(levels: Array(controller.levels.suffix(Self.waveformBars)), color: controller.mode.tint)
                    .frame(height: 20)
                    .padding(.horizontal, 2)
                languageChip
                // 確定は Fn、キャンセルは Esc で行うので、バーにはボタンを置かない
                Text(timeString(controller.elapsed))
                    .font(.ui(11, .medium).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.trailing, 7)
            case .processing:
                Spinner(tint: controller.mode.tint)
                    .frame(width: 26, height: 26)
                ShimmerText(text: processingLabel)
                    .padding(.trailing, 9)
            case .message(let text, let isError):
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isError ? Palette.warning : Palette.success)
                    .padding(.leading, 6)
                Text(text)
                    .font(.ui(12, .medium))
                    .foregroundStyle(Palette.text)
                    .lineLimit(3)
                    .frame(maxWidth: 420, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, 8)
            case .idle:
                EmptyView()
            }
        }
        .padding(5)
        .frame(minHeight: 36)
        .background(BarBackground())
        .fixedSize()
    }

    private var modeBadge: some View {
        Image(systemName: controller.mode.symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(controller.mode.tint)
            .frame(width: 26, height: 26)
            .background(Circle().fill(controller.mode.tint.opacity(0.14)))
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
                chipLabel(s.currentTranslationTarget, among: s.translationTargets, symbol: "arrow.right")
            }
            .buttonStyle(.plain)
        } else if s.dictationLanguages.count > 1 && s.sttProvider == .apple {
            MenuButton(entries: {
                s.dictationLanguages.map { lang in
                    .item(Languages.name(lang), checked: lang == s.currentDictationLanguage) { controller.changeDictationLanguage(lang) }
                }
            }) {
                chipLabel(s.currentDictationLanguage, among: s.dictationLanguages, symbol: nil)
            }
            .buttonStyle(.plain)
        }
    }

    /// 言語は短いコード（JA・EN）で出し、正式な名前はメニューとツールチップで見せる。
    /// 文字幅は JA と EN で違うので、選べる言語のうち一番幅の広いコードに合わせて、切り替えてもチップの幅を変えない。
    private func chipLabel(_ lang: String, among langs: [String], symbol: String?) -> some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 8.5, weight: .bold)).foregroundStyle(controller.mode.tint) }
            ZStack {
                ForEach(langs, id: \.self) { Text(Languages.shortName($0, among: langs)).hidden() }
                Text(Languages.shortName(lang, among: langs))
            }
            .font(.ui(10.5, .semibold))
            .tracking(0.4)
            .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 6.5, weight: .bold)).foregroundStyle(Palette.textTertiary)
        }
        .foregroundStyle(Palette.text)
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .frame(height: 22)
        .background(Capsule().fill(Palette.hover))
        .contentShape(Capsule())
        .help(Languages.name(lang))
        .accessibilityLabel(Languages.name(lang))
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 音声バーの下地。ダークでは上の縁にだけ細い光を入れて、面の立体感を出す。
private struct BarBackground: View {
    var body: some View {
        // 線（strokeBorder・stroke）で縁を描くと、カプセルの左右の端の外に縦線が出る。外側を縁の色で塗り、1pt 内側を面の色で塗って縁にする。
        let shape = Capsule()
        ZStack {
            shape.fill(Palette.panelBorder)
            shape.fill(LinearGradient(colors: [Color.dynamic(0xffffff, 0xffffff, lightAlpha: 0, darkAlpha: 0.08), .clear],
                                      startPoint: .top, endPoint: .center))
            shape.inset(by: 1).fill(Palette.panel)
        }
    }
}

struct Waveform: View {
    var levels: [Float]
    var color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 1.5) {
            ForEach(levels.indices, id: \.self) { i in
                let level = CGFloat(levels[i])
                Capsule()
                    .fill(color.opacity(0.45 + 0.55 * Double(min(level * 1.4, 1))))
                    .frame(width: 2, height: max(3, level * 20))
            }
        }
        .mask(LinearGradient(stops: [.init(color: .black.opacity(0.15), location: 0), .init(color: .black, location: 0.3)],
                             startPoint: .leading, endPoint: .trailing))
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
                    ScreenPlacement.hide(panel)
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
