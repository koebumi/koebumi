import AppKit
import SwiftUI

// MARK: - 色

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255,
                  alpha: alpha)
    }
}

extension Color {
    /// ライトとダークで切り替わる色。ウィンドウの外観（NSApp.appearance）に追従する。
    static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark, alpha: darkAlpha)
                : NSColor(hex: light, alpha: lightAlpha)
        })
    }
}

/// Aside の配色。ライトはヘルプセンター（docs.aside.com）、ダークはアプリ本体の設定画面に合わせている。
enum Palette {
    // 面
    static let shell = Color.dynamic(0xf5f6f8, 0x151618)
    static let shellGlass = Color.dynamic(0xf5f6f8, 0x151618, lightAlpha: 0.12, darkAlpha: 0.16)
    static let panel = Color.dynamic(0xffffff, 0x1b1c1f)
    static let panelBorder = Color.dynamic(0xe3e5e9, 0x2a2c31)
    static let card = Color.dynamic(0xf7f8fa, 0x232428)
    static let cardBorder = Color.dynamic(0xeceef1, 0x2b2d32)
    static let divider = Color.dynamic(0xe9ebee, 0x2d2f34)
    static let control = Color.dynamic(0xffffff, 0x1b1c1f)
    static let controlHover = Color.dynamic(0xf6f7f9, 0x222327)
    static let controlBorder = Color.dynamic(0xdde0e5, 0x36383e)
    static let track = Color.dynamic(0xeef0f3, 0x17181b)
    static let thumb = Color.dynamic(0xffffff, 0x303237)
    static let meter = Color.dynamic(0xe6e8ec, 0x313338)
    static let hover = Color.dynamic(0x0b0f19, 0xffffff, lightAlpha: 0.045, darkAlpha: 0.055)
    static let selection = Color.dynamic(0x0b0f19, 0xffffff, lightAlpha: 0.075, darkAlpha: 0.1)

    // 文字
    static let text = Color.dynamic(0x202428, 0xeceef0)
    static let textSecondary = Color.dynamic(0x626970, 0xa0a5ad)
    static let textTertiary = Color.dynamic(0x9aa1a9, 0x6c717a)
    static let sidebarText = Color.dynamic(0x41464c, 0xc9ccd2)

    // アクセント
    static let accent = Color.dynamic(0x0284c7, 0x38bdf8)
    static let accentText = Color.dynamic(0xffffff, 0x082f49)
    static let inverse = Color.dynamic(0x171717, 0xf4f4f5)
    static let inverseText = Color.dynamic(0xfafafa, 0x171717)
    static let success = Color.dynamic(0x16a34a, 0x4ade80)
    static let warning = Color.dynamic(0xd97706, 0xfbbf24)
    static let danger = Color.dynamic(0xdc2626, 0xf87171)
    static let teal = Color.dynamic(0x0d9488, 0x2dd4bf)
    static let violet = Color.dynamic(0x7c3aed, 0xa78bfa)
}

extension Mode {
    var tint: Color {
        switch self {
        case .dictate: return Palette.accent
        case .translate: return Palette.teal
        case .ask: return Palette.violet
        }
    }
}

extension Font {
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

enum Metrics {
    static let sidebarWidth: CGFloat = 236
    static let titlebarHeight: CGFloat = 40
    static let panelRadius: CGFloat = 14
    static let cardRadius: CGFloat = 12
    static let contentWidth: CGFloat = 700
}

extension EnvironmentValues {
    /// `--snapshot` で描画中。ウィンドウ越しのぼかしは画像に写らないので、代わりの背景を描く。
    @Entry var isSnapshot = false
}

// MARK: - 背景

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// サイドバーとタイトルバーの下地。透明のときはデスクトップをぼかして透かす。
struct ShellBackground: View {
    var material: SidebarMaterial
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        switch material {
        case .tinted:
            Palette.shell
        case .transparent:
            ZStack {
                if isSnapshot {
                    SnapshotWallpaper()
                    Color.dynamic(0xf4f5f7, 0x1d1e21, lightAlpha: 0.74, darkAlpha: 0.8)
                } else {
                    VisualEffect()
                }
                Palette.shellGlass
            }
        }
    }
}

/// スナップショット用の壁紙（ぼかしたデスクトップの代わり）
struct SnapshotWallpaper: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 0.95), Color(red: 0.62, green: 0.48, blue: 0.92), Color(red: 0.95, green: 0.62, blue: 0.7)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - ロゴ

/// オウムの横顔のモノクロのマーク（アプリアイコンと同じ形）
struct SpeakMark: View {
    var size: CGFloat = 18
    var color: Color = Palette.text

    var body: some View {
        ParrotShape()
            .fill(color)
            .frame(width: size, height: size)
    }

    /// メニューバー用。テンプレート画像なので、メニューバーの明暗に合わせて色が変わる。
    /// 録音中は wideOpen でくちばしを大きく開けた形にする。
    static func menuBarImage(wideOpen: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(ParrotShape(wideOpen: wideOpen).path(in: rect.insetBy(dx: 1, dy: 1)).cgPath)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Speak"
        return image
    }
}

/// アプリアイコン（Resources/AppIcon.icon）の頭とくちばしを 1×1 に収めた形。目は抜いてある。
private struct ParrotShape: Shape {
    var wideOpen = false

    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var head = Path()
        head.move(to: pt(0.7174, 0.3083))
        head.addCurve(to: pt(0.5037, 0.1562), control1: pt(0.6707, 0.2192), control2: pt(0.6077, 0.1813))
        head.addCurve(to: pt(0.2085, 0), control1: pt(0.381, 0.1265), control2: pt(0.3062, 0.1067))
        head.addCurve(to: pt(0.194, 0.074), control1: pt(0.1973, 0.0234), control2: pt(0.194, 0.0492))
        head.addCurve(to: pt(0.3783, 0.2396), control1: pt(0.194, 0.1791), control2: pt(0.2781, 0.222))
        head.addCurve(to: pt(0.0231, 0.1516), control1: pt(0.2468, 0.2511), control2: pt(0.1189, 0.2187))
        head.addCurve(to: pt(0.2817, 0.3499), control1: pt(0.0135, 0.2877), control2: pt(0.1045, 0.3672))
        head.addCurve(to: pt(0.0391, 0.3763), control1: pt(0.1882, 0.3881), control2: pt(0.1345, 0.3911))
        head.addCurve(to: pt(0.2322, 0.4954), control1: pt(0.0504, 0.4571), control2: pt(0.1304, 0.524))
        head.addCurve(to: pt(0.1494, 0.7154), control1: pt(0.1805, 0.5543), control2: pt(0.1494, 0.6387))
        head.addCurve(to: pt(0.565, 0.9998), control1: pt(0.1494, 0.8477), control2: pt(0.3032, 0.9998))
        head.addCurve(to: pt(0.7355, 0.9993), control1: pt(0.628, 1.0004), control2: pt(0.6882, 0.9993))
        head.addCurve(to: pt(0.7372, 0.9418), control1: pt(0.7386, 0.9778), control2: pt(0.7386, 0.9616))
        head.addCurve(to: pt(0.6451, 0.625), control1: pt(0.7276, 0.7944), control2: pt(0.6451, 0.7625))
        head.addCurve(to: pt(0.7823, 0.329), control1: pt(0.6451, 0.5201), control2: pt(0.7182, 0.389))
        head.addCurve(to: pt(0.7174, 0.3083), control1: pt(0.7603, 0.3188), control2: pt(0.7386, 0.3128))
        head.closeSubpath()

        var beak = Path()
        beak.move(to: pt(0.783, 0.3289))
        beak.addCurve(to: pt(0.6452, 0.6114), control1: pt(0.7123, 0.3961), control2: pt(0.6499, 0.522))
        beak.addCurve(to: pt(0.9775, 0.5104), control1: pt(0.755, 0.5743), control2: pt(0.8832, 0.5335))
        beak.addCurve(to: pt(0.783, 0.3289), control1: pt(0.9531, 0.429), control2: pt(0.8612, 0.3586))
        beak.closeSubpath()
        var lower = Path()
        if wideOpen {
            // 大きく開けた下のくちばし。口の角から 40° 下へ向け、下の縁を喉につなぐ
            lower.move(to: pt(0.6452, 0.6114))
            lower.addLine(to: pt(0.87, 0.8))
            lower.addCurve(to: pt(0.69, 0.85), control1: pt(0.83, 0.845), control2: pt(0.76, 0.86))
            lower.addLine(to: pt(0.6, 0.7))
        } else {
            lower.move(to: pt(0.6735, 0.638))
            lower.addCurve(to: pt(0.756, 0.808), control1: pt(0.6812, 0.7073), control2: pt(0.723, 0.7725))
            lower.addCurve(to: pt(0.9051, 0.7219), control1: pt(0.802, 0.7847), control2: pt(0.8625, 0.7489))
            lower.addCurve(to: pt(0.9395, 0.6903), control1: pt(0.9199, 0.712), control2: pt(0.9315, 0.7002))
            lower.addLine(to: pt(0.6735, 0.638))
        }
        lower.closeSubpath()
        beak.addPath(lower)

        let r = 0.055
        let eye = Path(ellipseIn: CGRect(origin: pt(0.5211 - r, 0.4689 - r),
                                         size: CGSize(width: 2 * r * rect.width, height: 2 * r * rect.height)))
        // 頭とくちばしは辺が接しているだけなので、くちばしを少し太らせて重ね、継ぎ目の線を消す
        let seamless = beak.union(beak.strokedPath(StrokeStyle(lineWidth: rect.width * 0.012, lineJoin: .round)))
        return head.union(seamless).subtracting(eye)
    }
}

// MARK: - ボタン

struct AsideButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, accent, ghost, destructive, field }
    var kind: Kind = .secondary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        AsideButtonBody(configuration: configuration, kind: kind, compact: compact)
    }
}

extension ButtonStyle where Self == AsideButtonStyle {
    static var aside: AsideButtonStyle { AsideButtonStyle() }
    static func aside(_ kind: AsideButtonStyle.Kind = .secondary, compact: Bool = false) -> AsideButtonStyle {
        AsideButtonStyle(kind: kind, compact: compact)
    }
}

private struct AsideButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: AsideButtonStyle.Kind
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 7 : 8, style: .continuous)
        configuration.label
            .labelStyle(TightLabelStyle())
            .font(.ui(compact ? 12 : 13, kind == .field ? .regular : .medium))
            .lineLimit(1)
            .padding(.horizontal, compact ? 9 : (kind == .field ? 10 : 12))
            .frame(height: compact ? 24 : 30)
            .foregroundStyle(foreground)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .overlay(shape.fill(Color.black.opacity(configuration.isPressed ? 0.06 : 0)))
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering = $0 && isEnabled }
    }

    private var fill: Color {
        switch kind {
        case .primary: return Palette.inverse.opacity(hovering ? 0.86 : 1)
        case .accent: return Palette.accent.opacity(hovering ? 0.88 : 1)
        case .secondary, .field: return hovering ? Palette.controlHover : Palette.control
        case .ghost: return hovering ? Palette.hover : .clear
        case .destructive: return hovering ? Palette.danger.opacity(0.08) : Palette.control
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Palette.inverseText
        case .accent: return Palette.accentText
        case .secondary, .field: return Palette.text
        case .ghost: return hovering ? Palette.text : Palette.textSecondary
        case .destructive: return Palette.danger
        }
    }

    private var border: Color {
        switch kind {
        case .secondary, .field: return Palette.controlBorder
        case .destructive: return Palette.danger.opacity(hovering ? 0.4 : 0.25)
        default: return .clear
        }
    }
}

struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 11.5, weight: .semibold))
            configuration.title
        }
    }
}

/// 枠のないアイコンだけのボタン。ホバーで背景が出る。
struct IconButton: View {
    var symbol: String
    var help: String
    var size: CGFloat = 26
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Palette.text : Palette.textSecondary)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Palette.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .help(help)
        .onHover { hovering = $0 && isEnabled }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - メニュー

/// AppKit のメニューを出すボタンの中身。SwiftUI の Menu はラベルの見た目を変えられないので NSMenu を使う。
enum MenuEntry {
    case item(String, symbol: String? = nil, checked: Bool = false, destructive: Bool = false, enabled: Bool = true, action: () -> Void)
    case header(String)
    case separator
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { handler() }
}

final class MenuAnchor {
    weak var view: NSView?
}

private struct MenuAnchorView: NSViewRepresentable {
    let anchor: MenuAnchor
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}

@MainActor
enum MenuPresenter {
    static func present(_ entries: [MenuEntry], from anchor: MenuAnchor, trailing: Bool) {
        guard let view = anchor.view else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .header(let title):
                menu.addItem(.sectionHeader(title: title))
            case let .item(title, symbol, checked, destructive, enabled, action):
                let item = ClosureMenuItem(title: title, handler: action)
                item.state = checked ? .on : .off
                item.isEnabled = enabled
                if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
                if destructive {
                    item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.systemRed])
                }
                menu.addItem(item)
            }
        }
        menu.minimumWidth = view.bounds.width
        let x = trailing ? view.bounds.width - max(menu.size.width, view.bounds.width) : 0
        let y = view.isFlipped ? view.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: view)
    }
}

struct MenuButton<Label: View>: View {
    var trailing = false
    var entries: () -> [MenuEntry]
    @ViewBuilder var label: Label
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button {
            MenuPresenter.present(entries(), from: anchor, trailing: trailing)
        } label: {
            label
        }
        .background(MenuAnchorView(anchor: anchor))
    }
}

/// 値と ⌃⌄ を並べたポップアップ（Aside の設定画面のセレクタ）
struct PopupPicker<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [Value]
    var title: (Value) -> String
    var symbol: ((Value) -> String?)? = nil
    var minWidth: CGFloat = 0

    var body: some View {
        MenuButton(entries: {
            options.map { option in
                .item(title(option), symbol: symbol?(option) ?? nil, checked: option == selection) { selection = option }
            }
        }) {
            HStack(spacing: 8) {
                if let s = symbol?(selection) ?? nil {
                    Image(systemName: s).font(.system(size: 12)).foregroundStyle(Palette.textSecondary)
                }
                Text(title(selection)).lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(minWidth: minWidth)
        }
        .buttonStyle(.aside(.field))
        .fixedSize()
    }
}

// MARK: - 入力

struct AsideSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Capsule()
            .fill(isOn ? Palette.accent : Color.dynamic(0xd3d7dd, 0x3a3d43))
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1)
                    .padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture {
                guard isEnabled else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { isOn.toggle() }
            }
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? t("オン", "On") : t("オフ", "Off"))
            .accessibilityAction { isOn.toggle() }
    }
}

struct FieldChrome: ViewModifier {
    var focused: Bool
    var height: CGFloat = 30

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        content
            .textFieldStyle(.plain)
            .focusEffectDisabled()
            .font(.ui(13))
            .foregroundStyle(Palette.text)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(shape.fill(Palette.control))
            .overlay(shape.strokeBorder(focused ? Palette.accent.opacity(0.85) : Palette.controlBorder, lineWidth: 1))
            .background(
                RoundedRectangle(cornerRadius: 10.5, style: .continuous)
                    .stroke(Palette.accent.opacity(focused ? 0.2 : 0), lineWidth: 3)
                    .padding(-1.5)
            )
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

struct AsideTextField: View {
    var placeholder: String
    @Binding var text: String
    var secure = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.textTertiary))
            } else {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.textTertiary))
            }
        }
        .focused($focused)
        .onSubmit(onSubmit)
        .modifier(FieldChrome(focused: focused))
    }
}

/// 複数行の入力欄
struct AsideTextEditor: View {
    @Binding var text: String
    var minHeight: CGFloat = 90
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        TextEditor(text: $text)
            .font(.ui(13.5))
            .foregroundStyle(Palette.text)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .focusEffectDisabled()
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
            .frame(minHeight: minHeight)
            .background(shape.fill(Palette.control))
            .overlay(shape.strokeBorder(focused ? Palette.accent.opacity(0.85) : Palette.controlBorder, lineWidth: 1))
            .background(
                RoundedRectangle(cornerRadius: 12.5, style: .continuous)
                    .stroke(Palette.accent.opacity(focused ? 0.2 : 0), lineWidth: 3)
                    .padding(-1.5)
            )
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

struct SearchField: View {
    var placeholder: String
    @Binding var text: String
    var shortcut: [String] = []
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Palette.textSecondary))
                .focused(focus)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(.plain)
            } else if !shortcut.isEmpty && !focus.wrappedValue {
                HStack(spacing: 3) { ForEach(shortcut, id: \.self) { KeyCap(text: $0, compact: true) } }
            }
        }
        .modifier(FieldChrome(focused: focus.wrappedValue, height: 32))
    }
}

/// スライドする選択インジケータ付きのセグメント
struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [Value]
    var title: (Value) -> String
    var symbol: ((Value) -> String)? = nil
    var iconOnly = false
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = option }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol { Image(systemName: symbol(option)).font(.system(size: 11.5, weight: .medium)) }
                        if !iconOnly { Text(title(option)) }
                    }
                    .font(.ui(12.5, selected ? .medium : .regular))
                    .foregroundStyle(selected ? Palette.text : Palette.textSecondary)
                    .padding(.horizontal, iconOnly ? 0 : 11)
                    .frame(width: iconOnly ? 26 : nil, height: 24)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Palette.thumb)
                                .shadow(color: .black.opacity(0.1), radius: 1, y: 0.5)
                                .matchedGeometryEffect(id: "thumb", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(title(option))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.track))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.cardBorder))
    }
}

// MARK: - 小物

struct KeyCap: View {
    var text: String
    var compact = false

    var body: some View {
        Text(text)
            .font(.system(size: compact ? 10.5 : 11, weight: .medium))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, compact ? 4 : 6)
            .frame(minWidth: compact ? 18 : 22, minHeight: compact ? 18 : 22)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.control))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.controlBorder))
            .shadow(color: .black.opacity(0.05), radius: 0, y: 1)
    }
}

struct ShortcutKeys: View {
    var shortcut: Shortcut
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(shortcut.display.components(separatedBy: " + ").enumerated()), id: \.offset) { _, part in
                KeyCap(text: part, compact: compact)
            }
        }
    }
}

struct Badge: View {
    enum Tone { case accent, neutral, success, warning, danger }
    var text: String
    var tone: Tone = .accent
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(.ui(11, .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .frame(height: 19)
        .background(Capsule().fill(tone == .neutral ? Palette.hover : color.opacity(0.12)))
    }

    private var color: Color {
        switch tone {
        case .accent: return Palette.accent
        case .neutral: return Palette.textSecondary
        case .success: return Palette.success
        case .warning: return Palette.warning
        case .danger: return Palette.danger
        }
    }
}

/// 角丸の四角に入ったアイコン（ヘルプセンターのカードと同じ）
struct IconTile: View {
    var symbol: String
    var tint: Color = Palette.accent
    var size: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(shape.fill(tint.opacity(0.1)))
            .overlay(shape.strokeBorder(tint.opacity(0.16)))
    }
}

struct ProgressBar: View {
    var value: Double
    var tint: Color = Palette.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.meter)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.smooth(duration: 0.5), value: value)
    }
}

// MARK: - レイアウト

/// 1 ページ分のスクロール領域。上下の端はフェードさせる。
struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .frame(maxWidth: Metrics.contentWidth, alignment: .leading)
                .padding(.horizontal, 44)
                .padding(.top, 46)
                .padding(.bottom, 72)
                .frame(maxWidth: .infinity)
        }
        .mask(EdgeFade())
        // タイトルバーの安全領域に接していると、macOS 26 はスクロールビューをツールバーの下まで伸ばし、
        // トップバーのボタンへのクリックを奪う。1pt 離して伸ばさないようにする。
        .padding(.top, 1)
    }
}

struct EdgeFade: View {
    var top: CGFloat = 14
    var bottom: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: top)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: bottom)
        }
    }
}

struct PageHeader<Trailing: View>: View {
    var eyebrow: String?
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.ui(12.5, .medium))
                    .foregroundStyle(Palette.accent)
                    .padding(.bottom, 10)
            }
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.ui(30))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 0)
                trailing
            }
            if let subtitle {
                Text(subtitle)
                    .font(.ui(14))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(eyebrow: String? = nil, title: String, subtitle: String? = nil) {
        self.init(eyebrow: eyebrow, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// カードの外に置く小見出し（設定画面の「Tabs」など）
struct SectionLabel<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.ui(14, .medium)).foregroundStyle(Palette.textSecondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.ui(12.5))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.top, 10)
        .padding(.bottom, -10)
    }
}

extension SectionLabel where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// 行を区切り線でつなげた角丸のカード
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    if subview.id != subviews.first?.id {
                        Rectangle().fill(Palette.divider).frame(height: 1)
                    }
                    subview
                }
            }
        }
        .background(shape.fill(Palette.card))
        .overlay(shape.strokeBorder(Palette.cardBorder))
        .clipShape(shape)
    }
}

struct SettingRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var symbol: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.ui(13.5, .medium))
                    .foregroundStyle(Palette.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.ui(12.5))
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
    }
}

extension SettingRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, symbol: String? = nil) {
        self.init(title: title, subtitle: subtitle, symbol: symbol) { EmptyView() }
    }
}

struct ToggleRow: View {
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, subtitle: subtitle) { AsideSwitch(isOn: $isOn) }
    }
}

/// 自由な中身を行と同じ余白で並べる
struct RowContent<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
    }
}

/// カードの外に置く注記
struct Footnote: View {
    var text: String
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11)) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.ui(12))
        .foregroundStyle(Palette.textTertiary)
        .lineSpacing(2)
        .padding(.horizontal, 16)
        .padding(.top, -10)
    }
}

/// 汎用のカード
struct CardBox<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(Palette.card))
            .overlay(shape.strokeBorder(Palette.cardBorder))
    }
}

/// 警告や案内を出す帯
struct Callout<Trailing: View>: View {
    var symbol: String
    var text: String
    var tint: Color = Palette.warning
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(.ui(13)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(shape.fill(tint.opacity(0.08)))
        .overlay(shape.strokeBorder(tint.opacity(0.22)))
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 12) {
            IconTile(symbol: symbol, tint: Palette.textSecondary, size: 44)
            Text(title).font(.ui(15, .medium)).foregroundStyle(Palette.text)
            Text(message)
                .font(.ui(13))
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Palette.divider, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

/// シートの共通レイアウト（タイトル・説明・本文・ボタン）
struct SheetLayout<Content: View, Buttons: View>: View {
    var title: String
    var subtitle: String?
    var width: CGFloat = 480
    @ViewBuilder var content: Content
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.ui(22)).tracking(-0.3).foregroundStyle(Palette.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.ui(13))
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 18)
            VStack(alignment: .leading, spacing: 14) { content }
            HStack(spacing: 8) { buttons }
                .padding(.top, 22)
        }
        .padding(26)
        .frame(width: width)
        .background(Palette.panel)
    }
}

/// フォーム内の小さなラベル
struct FieldLabel: View {
    var text: String
    var body: some View {
        Text(text).font(.ui(12.5, .medium)).foregroundStyle(Palette.textSecondary)
    }
}

/// アプリのアイコン。履歴の行ごとに引くと重いので覚えておく。
@MainActor
enum AppIconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(_ bundleID: String) -> NSImage? {
        if let icon = icons[bundleID] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }
}

struct AppIcon: View {
    var bundleID: String
    var size: CGFloat = 28

    var body: some View {
        if let icon = AppIconCache.icon(bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            IconTile(symbol: "app", tint: Palette.textSecondary, size: size)
        }
    }
}

/// 時間の表記（ホーム・履歴で使う）
func relativeDate(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: L10n.current == .en ? "en_US" : "ja_JP")
    f.doesRelativeDateFormatting = true
    f.dateStyle = .short
    f.timeStyle = .short
    return f.string(from: date)
}
