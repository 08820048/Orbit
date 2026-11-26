import Foundation
import Sparkle

/// Software updates through Sparkle.
///
/// Only a packaged build (`Orbit.app` made by `scripts/build-app.sh`, which writes the feed URL and the public key into
/// Info.plist) can update itself. `swift run` and bare debug binaries just show their version.
/// Orbit sends no system profile and no usage data: an update check is one request for the appcast.
final class UpdateModel: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var lastCheck: Date?
    /// "已是最新版本", "发现新版本 0.2.0", "检查失败"; nil until a check has finished in this session.
    @Published private(set) var lastResult: String?
    @Published var automatic = true { didSet { if automatic != oldValue { controller?.updater.automaticallyChecksForUpdates = automatic } } }

    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []

    var isAvailable: Bool { controller != nil }

    /// "0.1.0（32）": marketing version and build number.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "—"
        let b = info?["CFBundleVersion"] as? String
        return b.map { "\(v)（\($0)）" } ?? v
    }

    override init() {
        super.init()
        guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller = c
        automatic = c.updater.automaticallyChecksForUpdates
        lastCheck = c.updater.lastUpdateCheckDate
        canCheck = c.updater.canCheckForUpdates
        observations = [
            c.updater.observe(\.canCheckForUpdates) { [weak self] u, _ in
                let value = u.canCheckForUpdates
                DispatchQueue.main.async { self?.canCheck = value }
            },
            c.updater.observe(\.lastUpdateCheckDate) { [weak self] u, _ in
                let value = u.lastUpdateCheckDate
                DispatchQueue.main.async { self?.lastCheck = value }
            },
        ]
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    // MARK: SPUUpdaterDelegate

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        DispatchQueue.main.async { self.lastResult = "已是最新版本" }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let name = item.displayVersionString
        DispatchQueue.main.async { self.lastResult = "发现新版本 \(name)" }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        // "No update available" also arrives here as an error; it is not a failure.
        guard let error = error as NSError?, error.code != Int(SUError.noUpdateError.rawValue) else { return }
        DispatchQueue.main.async { self.lastResult = "检查失败" }
    }
}
