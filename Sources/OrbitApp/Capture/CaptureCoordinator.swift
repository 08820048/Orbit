import AppKit
import Combine
import OrbitCore

/// Runs a screenshot from shortcut to saved file: permission, frozen screens, selection, saving, indexing, clipboard, sound,
/// the corner thumbnail. Also owns the screenshot library (index plus files).
@MainActor
final class CaptureCoordinator: ObservableObject {
    let settings: CaptureSettings
    private(set) var store: ScreenshotStore

    /// Bumped whenever the library changes, so views know to reload.
    @Published private(set) var libraryVersion = 0
    @Published var message: String?
    /// Set when a capture was attempted without permission; the window shows the guide.
    @Published var needsPermission = !ScreenPermission.granted
    /// Shortcuts the system would not give us (another app has them).
    @Published private(set) var conflicts: Set<CaptureAction> = []

    var onNeedPermission: (() -> Void)?

    private var overlay: SelectionOverlay?
    private var running = false
    /// The last region captured with the region tool, remembered across launches for 重复上一次区域.
    private(set) var lastRegion: RegionArea? = {
        UserDefaults.standard.data(forKey: "orbit.shot.lastRegion").flatMap { try? JSONDecoder().decode(RegionArea.self, from: $0) }
    }()
    /// Orbit hid itself to stay out of the picture; it comes back once the shot is saved or cancelled.
    private var hiddenForCapture = false
    private let quick = QuickAccessController()
    private let toolbar = CaptureToolbarController()
    /// Set while the floating menu swaps the running selection for another capture kind.
    private var switchingTo: CaptureAction?
    private var hotKeyIDs: [CaptureAction: UInt32] = [:]
    private var bag = Set<AnyCancellable>()

    init(settings: CaptureSettings) {
        self.settings = settings
        // ORBIT_STORE_PATH points the index somewhere else: used by the offscreen render check, never touches real data.
        let storeURL = ProcessInfo.processInfo.environment["ORBIT_STORE_PATH"].map { URL(fileURLWithPath: $0) } ?? ScreenshotStore.defaultURL
        store = (try? ScreenshotStore(url: storeURL)) ?? (try! ScreenshotStore(url: nil))
        registerHotKeys()
        settings.$combos.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.registerHotKeys() } }.store(in: &bag)
        try? store.reconcile()
        cleanOldScreenshots()
    }

    // MARK: Shortcuts

    func registerHotKeys() {
        for id in hotKeyIDs.values { HotKeyCenter.shared.unregister(id) }
        hotKeyIDs = [:]
        var failed: Set<CaptureAction> = []
        for action in CaptureAction.allCases {
            let id = HotKeyCenter.shared.register(settings.combo(action)) { [weak self] in self?.perform(action) }
            if let id { hotKeyIDs[action] = id } else { failed.insert(action) }
        }
        conflicts = failed
    }

    // MARK: Taking a screenshot

    func perform(_ action: CaptureAction, fromUI: Bool = false, delay: Int? = nil, menu: Bool = false) {
        guard !running else { return }
        guard ScreenPermission.granted else {
            ScreenPermission.request()
            needsPermission = true
            onNeedPermission?()
            return
        }
        needsPermission = false
        running = true
        Task { await run(action, fromUI: fromUI, delay: delay ?? settings.delaySeconds, menu: menu) }
    }

    private func run(_ action: CaptureAction, fromUI: Bool, delay: Int, menu: Bool = false) async {
        defer { if overlay == nil { running = false; restoreAfterCapture() } }
        do {
            if fromUI {
                // Started from a button or menu: get Orbit's own windows out of the picture first.
                NSApp.hide(nil)
                hiddenForCapture = true
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            if action == .delayed {
                guard await CountdownHUD.run(seconds: delay) else { return }
            }
            let source = NSWorkspace.shared.frontmostApplication?.localizedName
            switch action {
            case .fullscreen:
                let screens = try await CaptureService.freezeScreens(includeCursor: settings.includeCursor)
                if screens.count == 1 {
                    try finish(screens[0].image, kind: .fullscreen, source: source, scale: Double(screens[0].scale))
                } else {
                    // Several displays: the pointer turns into a camera and the user clicks the one to capture.
                    present(SelectionOverlay(frozen: screens, windows: [], mode: .display) { [weak self] r in self?.overlayDone(r, source: source) }, menu: menu, current: .fullscreen)
                }
            case .repeatLast:
                guard let area = lastRegion else { notice(String(localized: "还没有可以重复的区域"), String(localized: "先用「区域截图」截一次，之后就能用这个快捷键重复同一块区域。")); return }
                let screens = try await CaptureService.freezeScreens(includeCursor: settings.includeCursor)
                let center = CGPoint(x: area.rect.midX, y: area.rect.midY)
                guard let f = screens.first(where: { $0.screen.frame == area.screenFrame }) ?? screens.first(where: { $0.screen.frame.contains(center) }),
                      let image = f.crop(area.rect.offsetBy(dx: -f.screen.frame.minX, dy: -f.screen.frame.minY)) else {
                    notice(String(localized: "找不到上次的区域"), String(localized: "那块区域所在的显示器现在不可用。")); return
                }
                try finish(image, kind: .region, source: source, scale: Double(f.scale))
            case .region, .delayed, .window:
                async let frozen = CaptureService.freezeScreens(includeCursor: settings.includeCursor)
                async let windows = CaptureService.windows()
                let (f, w) = try await (frozen, windows)
                present(SelectionOverlay(frozen: f, windows: w, mode: action == .window ? .window : .region) { [weak self] r in self?.overlayDone(r, source: source) },
                        menu: menu, current: action == .window ? .window : .region)
            }
        } catch {
            fail(error)
        }
    }

    private func present(_ o: SelectionOverlay, menu: Bool, current: CaptureAction) {
        overlay = o
        o.show()
        if menu { showMenu(over: o, current: current) }
    }

    private func overlayDone(_ result: SelectionResult, source: String?) {
        overlay = nil
        toolbar.hide()
        if let next = switchingTo {
            // Picked "delayed" in the menu: carry on with that instead (still "running").
            switchingTo = nil
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await run(next, fromUI: false, delay: settings.delaySeconds)
            }
            return
        }
        handle(result, source: source)
    }

    /// The window's capture button: starts a region capture and shows the floating menu to switch kind or close.
    func startFromMenu() { perform(.region, fromUI: true, menu: true) }

    private func showMenu(over o: SelectionOverlay, current: CaptureAction) {
        toolbar.onPick = { [weak self, weak o] pick in
            guard let self, let o else { return }
            switch pick {
            case nil: o.cancel()
            case .region?: o.setMode(.region)
            case .window?: o.setMode(.window)
            case .fullscreen?: o.setMode(.display)
            case let next?: self.switchingTo = next; o.cancel()
            }
        }
        o.onModeChange = { [weak self] m in self?.toolbar.model.current = m == .window ? .window : m == .display ? .fullscreen : .region }
        toolbar.show(current: current)
    }

    /// Undoes the hiding done before a capture started from a button, so the window is there again afterwards.
    private func restoreAfterCapture() {
        guard hiddenForCapture else { return }
        hiddenForCapture = false
        if NSApp.isHidden { NSApp.unhide(nil) }
    }

    private func handle(_ result: SelectionResult, source: String?) {
        defer { restoreAfterCapture() }
        switch result {
        case .cancelled:
            running = false
        case let .region(image, scale, area):
            defer { running = false }
            lastRegion = area
            if let data = try? JSONEncoder().encode(area) { UserDefaults.standard.set(data, forKey: "orbit.shot.lastRegion") }
            do { try finish(image, kind: .region, source: source, scale: scale) } catch { fail(error) }
        case let .display(image, scale):
            running = false
            do { try finish(image, kind: .fullscreen, source: source, scale: scale) } catch { fail(error) }
        case let .window(window):
            Task {
                defer { running = false }
                do {
                    let image = try await CaptureService.captureWindow(window, includeCursor: settings.includeCursor)
                    let scale = NSScreen.screens.first(where: { $0.frame.intersects(window.frame) })?.backingScaleFactor ?? 2
                    try finish(image, kind: .window, source: window.scWindow.owningApplication?.applicationName ?? source, scale: Double(scale))
                } catch { fail(error) }
            }
        }
    }

    private func finish(_ image: CGImage, kind: CaptureKind, source: String?, scale: Double) throws {
        let record = try CaptureService.save(image, kind: kind, source: source, scale: scale, format: settings.format, folder: settings.folderURL)
        try store.add(record)
        libraryVersion += 1
        let thumb = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
        if settings.autoCopy { copy(record, image: thumb) }
        if settings.playSound { Self.playShutter() }
        if settings.showQuickPanel {
            showQuickPanel(for: record, image: thumb)
        }
    }

    private func showQuickPanel(for record: ScreenshotRecord, image: NSImage) {
        quick.show(record: record, image: image, seconds: settings.quickPanelSeconds, actions: .init(
            copy: { [weak self] in self?.copy(record) },
            edit: { [weak self] in self?.edit(record) },
            reveal: { [weak self] in self?.reveal(record) },
            delete: { [weak self] in self?.delete(record) },
            open: { NSWorkspace.shared.open(record.url) }))
    }

    /// Opens the editor for a screenshot, on the annotate page or (`beautify`) the beautify page.
    func edit(_ record: ScreenshotRecord, beautify: Bool = false) {
        EditorManager.shared.open(record, capture: self, beautify: beautify)
    }

    /// The editor saved a picture: index it (a new file or the replaced original) and show the result like a fresh capture.
    func didSaveEdited(_ record: ScreenshotRecord, image: CGImage) {
        try? store.add(record)
        libraryVersion += 1
        if settings.autoCopy { copy(record) }
        if settings.showQuickPanel {
            let scale = max(record.scale, 1)
            showQuickPanel(for: record, image: NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)))
        }
    }

    /// A short message for something that is not an error but needs saying (nothing to repeat yet…).
    private func notice(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

    private func fail(_ error: Error) {
        running = false
        if case CaptureError.noPermission = error { needsPermission = true; onNeedPermission?(); return }
        // macOS reports a missing permission as a generic ScreenCaptureKit error too.
        if !ScreenPermission.granted { needsPermission = true; onNeedPermission?(); return }
        message = error.localizedDescription
    }

    private static func playShutter() {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        (NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Grab"))?.play()
    }

    // MARK: Library

    /// Tells views to reload (used after the index was changed from outside this class).
    func libraryChanged() { libraryVersion += 1 }

    func records(kind: CaptureKind?, search: String) -> [ScreenshotRecord] {
        (try? store.records(kind: kind, search: search)) ?? []
    }

    var count: Int { (try? store.count()) ?? 0 }
    var totalBytes: Int64 { (try? store.totalBytes()) ?? 0 }

    /// Forgets screenshots whose files were deleted or moved outside Orbit.
    func reconcile() {
        if let dropped = try? store.reconcile(), dropped > 0 { libraryVersion += 1 }
    }

    func copy(_ record: ScreenshotRecord, image: NSImage? = nil) {
        guard let image = image ?? NSImage(contentsOf: record.url) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        if let data = try? Data(contentsOf: record.url) { pb.setData(data, forType: record.url.pathExtension.lowercased() == "png" ? .png : .tiff) }
    }

    func reveal(_ record: ScreenshotRecord) { NSWorkspace.shared.activateFileViewerSelecting([record.url]) }

    /// Moves the file to the Trash and forgets it.
    func delete(_ record: ScreenshotRecord) {
        try? FileManager.default.trashItem(at: record.url, resultingItemURL: nil)
        try? store.remove(id: record.id)
        libraryVersion += 1
    }

    /// Trashes every screenshot in the library.
    func deleteAll() {
        let all = (try? store.records()) ?? []
        for r in all { try? FileManager.default.trashItem(at: r.url, resultingItemURL: nil) }
        try? store.removeAll()
        libraryVersion += 1
    }

    /// Applies the "auto clean" setting (0 = never).
    func cleanOldScreenshots() {
        guard settings.autoCleanDays > 0,
              let cutoff = Calendar.current.date(byAdding: .day, value: -settings.autoCleanDays, to: Date()),
              let old = try? store.records(olderThan: cutoff), !old.isEmpty else { return }
        for r in old { try? FileManager.default.trashItem(at: r.url, resultingItemURL: nil); try? store.remove(id: r.id) }
        libraryVersion += 1
    }
}
