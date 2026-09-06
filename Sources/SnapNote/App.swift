import AppKit
import SwiftUI
import Carbon
import UniformTypeIdentifiers

@main
struct SnapNoteMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let document = Document()
    var window: NSWindow!
    var hotKey: EventHotKeyRef?
    var hotKeyHandler: EventHandlerRef?
    var keyMonitor: Any?
    var captureProcess: Process?
    var arrowLabelPopoverOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "SnapNote"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = CGSize(width: 680, height: 440)
        window.contentView = NSHostingView(rootView: Editor(document: document, app: self))
        window.delegate = self
        window.setFrameAutosaveName("SnapNoteEditor")
        window.center()
        if CommandLine.arguments.contains("--sample") { document.load(Sample.image()) }
        showEditor()
        registerHotKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showEditor(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        captureProcess?.terminate()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { finishText(); return true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let path = filenames.first, let image = NSImage(contentsOfFile: path) else {
            sender.reply(toOpenOrPrint: .failure); return
        }
        document.load(image); showEditor(); sender.reply(toOpenOrPrint: .success)
    }

    func showEditor() {
        guard window != nil else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context -> OSStatus in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { delegate.capture() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        let id = EventHotKeyID(signature: 0x534E4150, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_2), UInt32(cmdKey | shiftKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { showError("⌘⇧2 is already used by another app. Free that shortcut to capture from anywhere.") }
    }

    func capture() {
        guard !document.capturing else { return }
        finishText()
        // Ask only on capture, never on launch or when opening an existing image.
        if !CGPreflightScreenCaptureAccess() && !CGRequestScreenCaptureAccess() {
            showEditor()
            let alert = NSAlert()
            alert.messageText = "Allow SnapNote to capture your selection"
            alert.informativeText = "Enable SnapNote in System Settings → Privacy & Security → Screen & System Audio Recording. Then return and press ⌘⇧2. macOS may ask you to quit and reopen SnapNote."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn { openPermissions() }
            return
        }
        document.capturing = true
        let wasVisible = window.isVisible
        window.orderOut(nil)
        NSApp.hide(nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("snapnote-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", "-t", "png", url.path]
        let errors = Pipe(); process.standardError = errors
        captureProcess = process
        process.terminationHandler = { [weak self] process in
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                guard let self else { return }
                defer { try? FileManager.default.removeItem(at: url) }
                self.captureProcess = nil; self.document.capturing = false
                if let image = NSImage(contentsOf: url) {
                    self.document.load(image); self.showEditor()
                } else {
                    self.document.status = "Capture cancelled · Your last image is still here"
                    if wasVisible { self.showEditor() }
                    let message = String(data: errorData, encoding: .utf8) ?? ""
                    if message.localizedCaseInsensitiveContains("could not") || message.localizedCaseInsensitiveContains("denied") {
                        self.showError("Screen capture failed. Check SnapNote's screen recording permission in System Settings.")
                    }
                }
            }
        }
        // Let the editor disappear before the native crosshair starts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            do { try process.run() }
            catch {
                self.document.capturing = false; self.captureProcess = nil
                self.showEditor(); self.showError(error.localizedDescription)
            }
        }
    }

    func finishText() {
        func visit(_ view: NSView) {
            if let canvas = view as? AnnotationCanvas { canvas.finishText() }
            for child in view.subviews { visit(child) }
        }
        if let content = window?.contentView { visit(content) }
    }

    func output() throws -> Data? {
        finishText()
        guard let image = document.image else { return nil }
        return try Renderer.export(image: image, marks: document.marks, blurb: document.blurb, scale: document.pixelScale)
    }

    @objc func copyImage() {
        do {
            guard let data = try output() else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
            if let image = NSImage(data: data), let tiff = image.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
            document.status = "Copied ✓ · Paste into any app with ⌘V"
        } catch { showError(error.localizedDescription) }
    }

    @objc func save() {
        do {
            guard let data = try output() else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "SnapNote-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                do { try data.write(to: url, options: .atomic); self.document.status = "Saved \(url.lastPathComponent)" }
                catch { self.showError(error.localizedDescription) }
            }
        } catch { showError(error.localizedDescription) }
    }

    @objc func pasteImage() {
        if let image = NSImage(pasteboard: .general) { finishText(); document.load(image); showEditor() }
        else { document.status = "No image on the clipboard · Copy an image first" }
    }
    @objc func openImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { response in
            if response == .OK, let url = panel.url, let image = NSImage(contentsOf: url) { self.document.load(image) }
        }
    }
    func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    func showError(_ message: String) {
        showEditor()
        let alert = NSAlert(); alert.messageText = "SnapNote"; alert.informativeText = message
        alert.runModal()
    }

    func handleKey(_ event: NSEvent) -> NSEvent? {
        if arrowLabelPopoverOpen { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        // Popovers have their own window and field editor.
        let responder = event.window?.firstResponder ?? NSApp.keyWindow?.firstResponder ?? window?.firstResponder
        let editing = responder is NSTextView || responder is NSTextField
        if flags.contains(.command) {
            switch key {
            case "s": save(); return nil
            case "o": openImage(); return nil
            case "w": window.performClose(nil); return nil
            case "q": NSApp.terminate(nil); return nil
            case "c" where !editing || flags.contains(.shift): copyImage(); return nil
            case "v" where !editing: pasteImage(); return nil
            case "z" where !editing:
                if flags.contains(.shift) { document.redo() } else { document.undo() }; return nil
            default: return event
            }
        }
        if !editing, flags.intersection([.command, .control, .option]).isEmpty, flags.contains(.shift), key == "g" {
            let axis = document.selectedGuide?.guideAxis ?? document.guideAxis
            document.setGuideAxis(axis == .vertical ? .horizontal : .vertical)
            if document.selectedGuide == nil { document.selected = nil }
            document.tool = .guide; return nil
        }
        if !editing, flags.intersection([.command, .control, .option]).isEmpty, key == "[" || key == "]" {
            document.adjustSize(increase: key == "]"); return nil
        }
        if !editing, flags.intersection([.command, .control, .option]).isEmpty,
           let tool = Tool.allCases.first(where: { $0.key.lowercased() == key }) {
            finishText(); document.tool = tool; document.selected = nil; return nil
        }
        return event
    }

    func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit SnapNote", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem)
        let edit = NSMenuItem(); edit.title = "Edit"; let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        edit.submenu = editMenu; menu.addItem(edit); NSApp.mainMenu = menu
    }
}
