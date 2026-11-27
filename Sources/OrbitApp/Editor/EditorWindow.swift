import AppKit
import ImageIO
import OrbitCore
import SwiftUI

/// A distinct type so "the main window" can be told apart from editors when looking for it.
final class EditorWindow: NSWindow {}

/// One annotation editor window: loads the screenshot, hosts the editor, saves, and asks before losing changes.
@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    let model: EditorModel
    private let capture: CaptureCoordinator
    private(set) var window: NSWindow!
    private var skipPrompt = false

    init?(record: ScreenshotRecord, capture: CaptureCoordinator) {
        guard let src = CGImageSourceCreateWithURL(record.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        model = EditorModel(record: record, base: image)
        self.capture = capture
        super.init()

        let w = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 820, height: 560)
        w.backgroundColor = NSColor(srgbRed: 0.039, green: 0.059, blue: 0.11, alpha: 1)
        w.contentView = NSHostingView(rootView: EditorView(model: model, controller: self))
        w.delegate = self
        w.center()
        window = w
    }

    func show(mode: EditorModel.Mode? = nil) {
        if let mode { model.mode = mode }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Actions

    func copyToClipboard() {
        guard let image = model.renderOutput(), let data = try? CaptureService.encode(image, as: .png) else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .png)
    }

    /// Saves next to the original under a new "已编辑" name.
    func saveAsNew() {
        let suffix = model.mode == .beautify ? String(localized: "已美化") : String(localized: "已编辑")
        finish { image in try CaptureService.saveEdited(image, from: self.model.record, suffix: suffix) }
    }

    /// Replaces the original (it goes to the Trash first).
    func overwriteOriginal() {
        finish { image in try CaptureService.overwrite(image, original: self.model.record) }
    }

    private func finish(_ save: (CGImage) throws -> ScreenshotRecord) {
        // On the beautify page there is always something to save; on the annotate page only after an edit.
        guard model.isDirty || model.mode == .beautify else { requestClose(); return }
        guard let image = model.renderOutput() else { NSSound.beep(); return }
        do {
            let record = try save(image)
            capture.didSaveEdited(record, image: image)
            skipPrompt = true
            window.close()
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "无法保存")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func requestClose() { window.performClose(nil) }

    // MARK: Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty, !skipPrompt else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "要保存对这张截图的修改吗？")
        alert.informativeText = String(localized: "不保存的话，这些修改会丢失。")
        alert.addButton(withTitle: String(localized: "保存为新截图"))
        alert.addButton(withTitle: String(localized: "不保存"))
        alert.addButton(withTitle: String(localized: "取消"))
        alert.beginSheetModal(for: sender) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn: self.saveAsNew()
            case .alertSecondButtonReturn: self.skipPrompt = true; sender.close()
            default: break
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        EditorManager.shared.closed(model.record.id)
    }
}

@MainActor
final class EditorManager {
    static let shared = EditorManager()
    private var controllers: [UUID: EditorWindowController] = [:]

    func open(_ record: ScreenshotRecord, capture: CaptureCoordinator, mode: EditorModel.Mode? = nil) {
        if let existing = controllers[record.id] { existing.show(mode: mode); return }
        guard let c = EditorWindowController(record: record, capture: capture) else { NSSound.beep(); return }
        controllers[record.id] = c
        c.show(mode: mode)
    }

    fileprivate func closed(_ id: UUID) { controllers[id] = nil }
}
