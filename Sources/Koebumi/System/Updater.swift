import Combine
import Foundation
import Sparkle

/// Sparkle で新しい版を確かめて入れる。新しい版の情報（appcast.xml）は GitHub Releases に置く（scripts/release.sh）。
/// 配布用に作ったアプリ（Info.plist に SUFeedURL がある）でだけ動かす。swift run や CLI では何もしない
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    /// 1 日 1 回、自動で新しい版を確かめるか。値は Sparkle が保存する
    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    private init() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
