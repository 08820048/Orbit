import AppKit

/// Records which app is in front using NSWorkspace notifications. This is the fallback data
/// source when Full Disk Access is not granted, and fills gaps if Screen Time's layout changes.
///
/// Event-driven only (no polling), so idle CPU cost is zero. Must be used on the main actor.
@MainActor
public final class ForegroundMonitor {
    private let store: HistoryStore
    private let now: () -> Date
    private var current: (bundleID: String, start: Date)?
    private var observers: [NSObjectProtocol] = []
    /// Sessions shorter than this are app-switcher noise.
    static let minimumDuration: TimeInterval = 1

    public init(store: HistoryStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
    }

    public var isRunning: Bool { !observers.isEmpty }

    public func start() {
        guard !isRunning else { return }
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.switchTo(bundleID) }
        })
        // The user is away: close the open session so sleep/lock time is not counted.
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observe(ws, name) { [weak self] in self?.switchTo(nil) }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(ws, name) { [weak self] in self?.resumeFrontmost() }
        }
        let dnc = DistributedNotificationCenter.default()
        observe(dnc, Notification.Name("com.apple.screenIsLocked")) { [weak self] in self?.switchTo(nil) }
        observe(dnc, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in self?.resumeFrontmost() }
        resumeFrontmost()
    }

    /// Stops observing and saves the open session. Call on app termination.
    public func stop() {
        switchTo(nil)
        for o in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            DistributedNotificationCenter.default().removeObserver(o)
        }
        observers.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor () -> Void) {
        observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { action() }
        })
    }

    private func resumeFrontmost() {
        switchTo(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// Ends the current session (if any) and starts one for `bundleID` (if not nil).
    func switchTo(_ bundleID: String?) {
        let t = now()
        if let open = current {
            if open.bundleID == bundleID { return }
            if t.timeIntervalSince(open.start) >= Self.minimumDuration {
                let key = "mon:\(open.bundleID):\(Int64(open.start.timeIntervalSince1970 * 1000))"
                _ = try? store.insert([UsageSession(bundleID: open.bundleID, start: open.start, end: t,
                                                source: .monitor, sourceKey: key)])
            }
        }
        current = bundleID.map { ($0, t) }
    }
}
