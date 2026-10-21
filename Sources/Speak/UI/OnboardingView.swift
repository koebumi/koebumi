import Combine
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settingsStore: SettingsStore
    @EnvironmentObject var controller: DictationController
    @Environment(\.dismiss) private var dismiss
    @State private var micGranted = Permissions.microphoneGranted
    @State private var axGranted = Permissions.accessibilityGranted
    @State private var tryText = ""
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var doneCount: Int { (micGranted ? 1 : 0) + (axGranted ? 1 : 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 18) {
                SettingsGroup {
                    step(1, "mic", t("マイクへのアクセス", "Microphone access"),
                         t("話した声を録音するために使います。", "Used to record your voice."),
                         done: micGranted) {
                        Button(t("許可する", "Allow")) {
                            Task {
                                micGranted = await Permissions.requestMicrophone()
                                if !micGranted { Permissions.openMicrophoneSettings() }
                            }
                        }
                        .buttonStyle(.aside(.primary))
                    }
                    step(2, "accessibility", t("アクセシビリティ", "Accessibility"),
                         t("ショートカットの検知と、カーソル位置への入力に使います。システム設定で Speak をオンにしてください。",
                           "Used to detect shortcuts and type at your cursor. Turn on Speak in System Settings."),
                         done: axGranted) {
                        Button(t("設定を開く", "Open Settings")) {
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                        .buttonStyle(.aside(micGranted ? .primary : .secondary))
                    }
                    step(3, "globe", t("Fn（🌐）キーの設定", "Fn (🌐) key"),
                         t("システム設定 > キーボード の「🌐キーを押して」を「何もしない」にすると、Fn キーで音声入力できます。",
                           "In System Settings > Keyboard, set “Press 🌐 key to” to “Do Nothing” so Fn starts dictation."),
                         done: nil) {
                        Button(t("キーボード設定", "Keyboard settings")) { Permissions.openKeyboardSettings() }
                            .buttonStyle(.aside)
                    }
                    step(4, "cube", t("AI エンジン", "AI engines"),
                         t("音声認識: ", "Speech: ") + settingsStore.settings.sttTitle + "\n"
                             + t("整形: ", "Cleanup: ") + settingsStore.settings.llmProvider.title,
                         done: nil) {
                        Button(t("変更", "Change")) {
                            Navigation.shared.go(.engines)
                            finish()
                        }
                        .buttonStyle(.aside)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 5) {
                        Text(t("試してみましょう。下の欄をクリックし、", "Try it. Click the field below, press"))
                        ForEach(settingsStore.settings.dictateShortcuts.prefix(1)) { ShortcutKeys(shortcut: $0, compact: true) }
                        Text(t("を押して話します。", "and speak."))
                    }
                    .font(.ui(13))
                    .foregroundStyle(Palette.textSecondary)
                    AsideTextEditor(text: $tryText, minHeight: 72)
                }

                HStack {
                    Text(t("あとからサイドバーの「セットアップ」で開けます", "Reopen this anytime from Setup in the sidebar"))
                        .font(.ui(12))
                        .foregroundStyle(Palette.textTertiary)
                    Spacer()
                    Button(t("完了", "Done")) { finish() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.aside(.primary))
                }
            }
            .padding(24)
        }
        .frame(width: 600)
        .background(Palette.panel)
        .onReceive(timer) { _ in
            micGranted = Permissions.microphoneGranted
            let ax = Permissions.accessibilityGranted
            if ax && !axGranted { controller.hotkeys.start() }
            axGranted = ax
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            AuroraBackground()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    SpeakMark(size: 30)
                    Text(t("Speak のセットアップ", "Set up Speak"))
                        .font(.ui(24))
                        .tracking(-0.3)
                        .foregroundStyle(Palette.text)
                    Text(t("どのアプリでも、話すだけで整った文章を入力できるようにします。", "Speak lets you dictate polished text into any app."))
                        .font(.ui(13))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Text("\(doneCount) / 2")
                    .font(.ui(12, .medium).monospacedDigit())
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Palette.panel.opacity(0.7)))
                    .help(t("必要な許可", "Required permissions"))
            }
            .padding(24)
        }
        .frame(height: 168)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.panelBorder).frame(height: 1) }
    }

    private func finish() {
        settingsStore.settings.onboardingCompleted = true
        dismiss()
    }

    private func step(_ n: Int, _ symbol: String, _ title: String, _ detail: String, done: Bool?, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done == true ? Palette.success : Palette.hover)
                    .overlay(Circle().strokeBorder(done == true ? Color.clear : Palette.controlBorder))
                if done == true {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Text("\(n)").font(.ui(12, .semibold).monospacedDigit()).foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(width: 28, height: 28)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: done)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ui(13.5, .medium)).foregroundStyle(Palette.text)
                Text(detail)
                    .font(.ui(12.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if done == true {
                Badge(text: t("完了", "Done"), tone: .success)
            } else {
                action()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}
