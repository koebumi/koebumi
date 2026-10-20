import AVFoundation
import AppKit
import ApplicationServices
import ServiceManagement

enum Permissions {
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var microphoneDenied: Bool {
        let s = AVCaptureDevice.authorizationStatus(for: .audio)
        return s == .denied || s == .restricted
    }

    static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }

    static func openAppleIntelligenceSettings() {
        open("x-apple.systempreferences:com.apple.Siri-Settings.extension")
    }

    private static func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Speak: login item change failed: \(error)")
        }
    }
}

/// 開始・終了時のインタラクションサウンド（設定でオフにできる）
@MainActor
enum Sounds {
    static func start() { play("Tink") }
    static func stop() { play("Pop") }
    static func cancel() { play("Bottle") }
    static func error() { play("Basso") }

    private static func play(_ name: String) {
        guard SettingsStore.shared.settings.interactionSounds else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}
