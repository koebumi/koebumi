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
        func place() { Self.place(panel, hosting: hosting, on: screen, bottomOffset: bottomOffset) }
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

    /// 中身の大きさに合わせて、画面下中央に置き直す
    @MainActor
    static func place(_ panel: NSPanel, hosting: NSView, on screen: NSScreen?, bottomOffset: CGFloat) {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        guard let frame = screen?.visibleFrame, size.width > 0 else { return }
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + bottomOffset)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// フェードしてから隠す。消えている途中でまた出すことになったら（shouldShow が true なら）隠さない。
    /// alphaValue だけでは見分けられない。録音の開始でメインスレッドが止まると、フェードが 0 まで進んだ後で show が出す動きを始め、
    /// その後に完了が呼ばれる。そこで隠すと、alphaValue は 1 に戻るのにパネルは隠れたままになり、録音の間ずっとバーが出なかった。
    @MainActor
    static func hide(_ panel: NSPanel, duration: TimeInterval = 0.12, unless shouldShow: @escaping @MainActor () -> Bool) {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated {
                if panel.alphaValue == 0, !shouldShow() { panel.orderOut(nil) }
            }
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
        // ガラスは縁と影を自分で描く。ウインドウの影を重ねると、ガラス越しに透けて縁が黒く見える。
        panel.hasShadow = false
        panel.contentView = hosting
        controller.$phase.combineLatest(controller.$mode)
            .receive(on: RunLoop.main)
            .sink { [weak self] phase, _ in self?.update(phase: phase) }
            .store(in: &cancellables)
        // 書き起こしの札が出たり伸びたりすると高さと幅が変わるので、出ている画面の下中央に置き直す。
        // SwiftUI が大きさを決めた後に置く
        hosting.rootView.onResize = { [weak self] in
            DispatchQueue.main.async { self?.relayout() }
        }
        // ガラスの下地もバーの色に合わせる。テーマと同じなら Koebumi の外観に従う
        SettingsStore.shared.$settings.map(\.voiceBarAppearance).removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] appearance in
                switch appearance {
                case .theme: self?.panel.appearance = nil
                case .light: self?.panel.appearance = NSAppearance(named: .aqua)
                case .dark: self?.panel.appearance = NSAppearance(named: .darkAqua)
                }
            }
            .store(in: &cancellables)
    }

    private func update(phase: DictationController.Phase) {
        let shouldShow = { [controller] in controller.phase != .idle }
        if phase == .idle {
            // 札とバーを一緒にフェードする（VoiceBarView は消える間、消える前の中身を出し続ける）
            ScreenPlacement.hide(panel, duration: 0.2, unless: shouldShow)
            return
        }
        // バーのまわりの余白（VoiceBarView.margin）の分だけ下げ、見た目の位置を前と同じにする
        ScreenPlacement.show(panel, hosting: hosting, bottomOffset: Self.bottomOffset, while: shouldShow)
    }

    private static let bottomOffset = 28 - VoiceBarView.margin

    private func relayout() {
        guard panel.isVisible, controller.phase != .idle else { return }
        ScreenPlacement.place(panel, hosting: hosting, on: panel.screen ?? ScreenPlacement.activeScreen, bottomOffset: Self.bottomOffset)
    }
}

struct VoiceBarView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject var settings: SettingsStore
    /// 大きさが変わったら呼ぶ（パネルを画面の下中央に置き直す）
    var onResize: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot
    /// バーが消えていく間（.idle）に出し続ける、消える前の中身
    @State private var frozen: Shown?
    /// 札とバーの大きさと、パネルを縮めずに取っておく大きさ
    @State private var contentSize = CGSize.zero
    @State private var held = CGSize.zero

    /// バーと札に出す中身
    struct Shown: Equatable {
        var phase: DictationController.Phase
        var live: LiveTranscript

        /// 録音中に書き起こした内容は、バーの上に別の札で出す（バーの幅と位置は変えない）
        var showsCard: Bool { !live.text.isEmpty && (phase == .recording || phase == .processing) }
    }

    private var current: Shown { Shown(phase: controller.phase, live: controller.live) }

    var body: some View {
        // 消えていく間に中身を消すと、空のガラスがフェードして見える。消える前の見た目のまま消す
        let shown = controller.phase == .idle ? frozen ?? current : current
        // `--snapshot` では、札の見た目を確かめるため設定に関係なく描く
        let showsCard = shown.showsCard && (settings.settings.showLiveTranscript || isSnapshot)
        VStack(spacing: 8) {
            if showsCard {
                card(shown.live)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
            }
            bar(shown.phase)
        }
        .padding(Self.margin)
        // 札は 0.22 秒でふわっと出入りし、字が増えたら幅と高さを 0.25 秒でなめらかに広げる。動きを減らす設定では広げる動きをなくす
        .animation(.easeOut(duration: 0.22), value: showsCard)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: shown.live.text)
        .onGeometryChange(for: CGSize.self, of: \.size) { size in
            held = CGSize(width: max(held.width, size.width), height: max(held.height, size.height))
            contentSize = size
        }
        // 札が縮んだり消えたりするときは、動き終わるまでパネルを縮めない（パネルの端で札が切れないように）
        .task(id: contentSize) {
            try? await Task.sleep(for: .seconds(0.3))
            if !Task.isCancelled { held = contentSize }
        }
        .frame(minWidth: held.width, minHeight: held.height, alignment: .bottom)
        .onGeometryChange(for: CGSize.self, of: \.size) { _ in onResize() }
        .onChange(of: current, initial: true) { _, new in
            if new.phase != .idle { frozen = new }
        }
        // 消え終わったら、取っておいた中身を捨てる。次に出すときに前の札が消える動きを見せない
        .task(id: controller.phase == .idle) {
            guard controller.phase == .idle, frozen != nil else { return }
            try? await Task.sleep(for: .seconds(0.5))
            guard !Task.isCancelled else { return }
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { frozen = nil }
        }
    }

    private func card(_ live: LiveTranscript) -> some View {
        LiveTextCard(live: live)
            .font(.ui(13))
            .foregroundStyle(Palette.text)
            .lineLimit(2)
            .truncationMode(.head)
            .frame(maxWidth: 380, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            // 札を広げる間も、字は広げ終えた幅で先に並べる（広げる途中で折り返して、1 行の文が 2 行に見えないように）。
            // 広がりきるまでは字が札からはみ出すので、札の形で切る
            .clipShape(BarShape())
            .modifier(BarSurface(appearance: settings.settings.voiceBarAppearance))
            .fixedSize()
            .accessibilityElement()
            .accessibilityLabel(live.text)
    }

    private func bar(_ phase: DictationController.Phase) -> some View {
        Group {
            switch phase {
            // 録音中と処理中で同じ VoiceDots を使い続け、線が点に集まる動きをつなげる
            case .recording, .processing:
                let processing = phase == .processing
                // 確定は Fn、キャンセルは Esc で行うので、バーにはボタンを置かない
                HStack(spacing: 13) {
                    SymbolBadge(symbol: controller.mode.symbol)
                    VoiceDots(level: controller.level, processing: processing)
                        .accessibilityElement()
                        .accessibilityLabel(processing ? processingLabel : t("聞いています", "Listening"))
                    if showsLanguageChip {
                        // 処理中もチップを残してバーの幅を変えない（切り替えは録音中だけ効く）
                        languageChip
                            .allowsHitTesting(!processing)
                            .padding(.leading, -3)
                    }
                }
                .padding(.leading, 7)
                // 線を左のアイコンの右側の真ん中に置くと右に寄って見え、バー全体の真ん中に置くと右が空きすぎる。その間を取る。
                .padding(.trailing, showsLanguageChip ? 8 : 24)
                .frame(height: 42)
            // 録音中のバーと同じ高さ・同じ左の丸にそろえる
            case .message(let text, let isError):
                HStack(spacing: 12) {
                    SymbolBadge(symbol: isError ? "exclamationmark" : "checkmark")
                    Text(text)
                        .font(.ui(13, .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(3)
                        .frame(maxWidth: 420, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 7)
                .padding(.trailing, 18)
                .padding(.vertical, 7)
                .frame(minHeight: 42)
            case .idle:
                EmptyView()
            }
        }
        .modifier(BarSurface(appearance: settings.settings.voiceBarAppearance))
        .fixedSize()
    }

    /// ガラスの縁の光と影がウインドウの端で切れないよう、まわりに空ける透明な余白
    static let margin: CGFloat = 12

    private var processingLabel: String {
        switch controller.mode {
        case .dictate: return t("整えています…", "Polishing…")
        case .translate: return t("翻訳しています…", "Translating…")
        case .ask: return t("考えています…", "Thinking…")
        }
    }

    /// 言語のチップを出すか。翻訳では訳す先、言語を指定する認識エンジンでは話す言語を選べるようにする。
    private var showsLanguageChip: Bool {
        let s = settings.settings
        return controller.mode == .translate || (s.dictationLanguages.count > 1 && s.sttNeedsFixedLanguage)
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
        } else if s.dictationLanguages.count > 1 && s.sttNeedsFixedLanguage {
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
            if let symbol { Image(systemName: symbol).font(.system(size: 8.5, weight: .bold)).foregroundStyle(Palette.textSecondary) }
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
        .background(Capsule().fill(Color.dynamic(0xffffff, 0xffffff, lightAlpha: 0.55, darkAlpha: 0.14)))
        .contentShape(Capsule())
        .help(Languages.name(lang))
        .accessibilityLabel(Languages.name(lang))
    }
}

/// 音声バーの下地。macOS 26 の Liquid Glass で、後ろの画面をぼかして透かす。ホームの見本のバーでも使う。
/// ライト・ダークを選んだときは、後ろの画面が明るくても暗くても白・黒に見えるよう、ガラスに色を付ける。
struct BarSurface: ViewModifier {
    var appearance: VoiceBarAppearance
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.colorScheme) private var themeScheme

    func body(content: Content) -> some View {
        Group {
            if isSnapshot {
                // ガラスは画像に写らないので、すりガラスに近い色で塗る
                content.background(BarShape().fill(Color.dynamic(0xeef4fb, 0x2a2d35, lightAlpha: 0.86, darkAlpha: 0.86)))
            } else {
                content.glassEffect(glass, in: BarShape())
            }
        }
        .overlay(BarRim().allowsHitTesting(false))
        // 左の丸・線・文字の色もバーの色に合わせる
        .environment(\.colorScheme, scheme)
    }

    private var scheme: ColorScheme {
        switch appearance {
        case .theme: return themeScheme
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var glass: Glass {
        switch appearance {
        case .theme: return .regular
        case .light: return .regular.tint(.white.opacity(0.75))
        case .dark: return .regular.tint(Color(nsColor: NSColor(hex: 0x16171a, alpha: 0.75)))
        }
    }
}

/// ガラスの上の縁に入れる細い光と、上半分のつや。暗い背景の上でもバーの形がわかるようにする。
private struct BarRim: View {
    var body: some View {
        ZStack {
            BarShape().fill(LinearGradient(colors: [Color.dynamic(0xffffff, 0xffffff, lightAlpha: 0.18, darkAlpha: 0.06), .clear],
                                          startPoint: .top, endPoint: .center))
            // 線（strokeBorder）で描くとカプセルの左右の端の外に縦線が出るので、外形と 1pt 内側の形の差を塗る
            BarRing(width: 1)
                .fill(LinearGradient(colors: [Color.dynamic(0xffffff, 0xffffff, lightAlpha: 0.75, darkAlpha: 0.34),
                                              Color.dynamic(0x000000, 0xffffff, lightAlpha: 0.08, darkAlpha: 0.1)],
                                     startPoint: .top, endPoint: .bottom),
                      style: FillStyle(eoFill: true))
        }
    }
}

/// 音声バーの形。高さ 42pt の 1 行ではカプセルになり、メッセージが折り返して高くなっても角だけが丸い。
private struct BarShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: min(21, rect.height / 2), style: .circular).path(in: rect)
    }
}

/// BarShape の縁だけの形（外形から width だけ内側の形をくり抜く）
private struct BarRing: Shape {
    var width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = BarShape().path(in: rect)
        path.addPath(BarShape().path(in: rect.insetBy(dx: width, dy: width)))
        return path
    }
}

/// 声に合わせて伸びる 9 本の線。黙ると点に戻り、処理中は 3 つの点に集まって波打つ。
struct VoiceDots: View {
    var level: Float
    var processing: Bool
    @State private var motion = VoiceDotsMotion()
    @Environment(\.isSnapshot) private var isSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let still = isSnapshot || reduceMotion
        // ガラスの上では .primary などの前景色がガラス用の色に置き換わり、Canvas では何も描かれない。色をそのまま指定する。
        let ink = colorScheme == .dark ? Color.white.opacity(0.95) : Color(nsColor: NSColor(hex: 0x0b0d12))
        TimelineView(.animation(paused: isSnapshot)) { context in
            Canvas { gc, size in
                motion.step(to: context.date, level: Double(level), processing: processing, still: still)
                gc.fill(motion.path(in: size), with: .color(ink))
            }
        }
        .frame(width: VoiceDotsMotion.width, height: 42)
    }
}

/// VoiceDots の動き。描くたびに経過時間だけ進め、バネの速さや点の集まり具合を前のフレームから引き継ぐ。
final class VoiceDotsMotion {
    static let width: CGFloat = 52
    private static let count = 9
    private static let spacing = 6.2
    /// 線の太さ。黙っているときは、この大きさの点になる
    private static let barWidth = 1.8
    private static let maxHeight = 28.0
    /// 処理中の 3 つの点の大きさ・間隔・上下に動く幅
    private static let dotSize = 2.3
    private static let dotSpacing = 4.6
    private static let dotLift = 2.3
    private static let wavePeriod = 1.2

    private var heights = Array(repeating: VoiceDotsMotion.barWidth, count: VoiceDotsMotion.count)
    private var velocities = Array(repeating: 0.0, count: VoiceDotsMotion.count)
    /// 線ごとの揺れ方。同じ音量でも線ごとに高さを少しずつ変える
    private let wobble = (0..<VoiceDotsMotion.count).map { _ in
        (Double.random(in: 5...10), Double.random(in: 0...6.28), Double.random(in: 3...7), Double.random(in: 0...6.28))
    }
    private var envelope = 0.0
    private var time = 0.0
    private var lastDate: Date?
    private var still = false
    private var wasProcessing: Bool?
    /// 0 で 3 つの点、1 で 9 本の線。バーが出た直後は 3 つの点から広げる
    private var spreadFrom = 0.0, spreadTo = 0.0, spreadStart = 0.0

    private var spread: Double {
        let x = min(1, max(0, (time - spreadStart) / 0.33))
        let eased = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
        return spreadFrom + (spreadTo - spreadFrom) * eased
    }

    func step(to date: Date, level: Double, processing: Bool, still: Bool) {
        let dt = lastDate.map { min(0.05, max(0, date.timeIntervalSince($0))) } ?? 0
        lastDate = date
        time += dt
        self.still = still
        if processing != wasProcessing {
            spreadFrom = wasProcessing == nil ? 0 : spread
            spreadTo = processing ? 0 : 1
            // 処理に入るときは、線が点に戻るのを少し待ってから集める
            spreadStart = still ? time - 1 : time + (processing ? 0.2 : 0.1)
            wasProcessing = processing
        }

        // 声が大きくなるときはすぐ追い、小さくなるときはゆっくり下げる
        if still {
            envelope = level
        } else {
            let tau = level > envelope ? 0.04 : 0.2
            envelope += (level - envelope) * (1 - exp(-dt / tau))
        }
        let loudness = min(1, envelope * 1.25)
        for i in 0..<Self.count {
            let c = (Double(i) - 4) / 4
            let profile = 0.45 + 0.55 * exp(-c * c * 1.6)  // 真ん中の線ほど高く伸びる
            let (f1, p1, f2, p2) = wobble[i]
            let jitter = 0.5 + 0.5 * sin(time * f1 + p1) * cos(time * f2 + p2)
            let target = processing ? Self.barWidth : Self.barWidth + (Self.maxHeight - Self.barWidth) * loudness * profile * (0.4 + 0.6 * jitter)
            if still {
                heights[i] = target
                velocities[i] = 0
                continue
            }
            // バネで追いかけ、少しだけ行き過ぎて戻る
            let k = 420.0, damping = 2 * 0.72 * k.squareRoot(), sub = dt / 3
            for _ in 0..<3 {
                velocities[i] += (k * (target - heights[i]) - damping * velocities[i]) * sub
                heights[i] += velocities[i] * sub
            }
            if heights[i] < Self.barWidth {
                heights[i] = Self.barWidth
                velocities[i] = 0
            }
        }
    }

    func path(in size: CGSize) -> Path {
        let cx = size.width / 2, cy = size.height / 2
        let s = spread
        let w = Self.dotSize + (Self.barWidth - Self.dotSize) * s
        var path = Path()
        for i in 0..<Self.count {
            // 3 本ずつ左・中・右の点に集まる。処理中の点は右から順に上下する
            let group = Double(i / 3 - 1)
            let dotX = cx + group * Self.dotSpacing
            let dotY = cy - (still ? 0 : Self.dotLift * sin(time * 2 * .pi / Self.wavePeriod + group * 1.15))
            let lineX = cx + (Double(i) - 4) * Self.spacing
            let x = dotX + (lineX - dotX) * s
            let y = dotY + (cy - dotY) * s
            let h = max(w, w + (heights[i] - Self.barWidth) * s)
            path.addRoundedRect(in: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h),
                                cornerSize: CGSize(width: w / 2, height: w / 2), style: .circular)
        }
        return path
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
                let shouldShow = { [controller] in controller.answer != nil }
                guard content != nil else {
                    ScreenPlacement.hide(panel, unless: shouldShow)
                    return
                }
                ScreenPlacement.show(panel, hosting: hosting, bottomOffset: 84, while: shouldShow)
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
                    SymbolBadge(symbol: "sparkles", size: 24)
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
                        Task { await controller.insert(text) }
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
