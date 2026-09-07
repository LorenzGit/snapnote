import SwiftUI
import ServiceManagement

struct Editor: View {
    @ObservedObject var document: Document
    let app: AppDelegate
    @State private var settings = false
    @State private var colors = false
    @State private var arrowOptions = false
    @State private var customArrowLabel = ""
    @State private var noteExpanded = false
    @State private var feedback: String?
    @FocusState private var noteFocused: Bool
    private let palette: [(String, NSColor)] = [
        ("Red", .systemRed), ("Orange", .systemOrange), ("Green", .systemGreen),
        ("Blue", .systemBlue), ("Purple", .systemPurple), ("Black", .black), ("White", .white)
    ]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.35)
            if document.image != nil {
                Group {
                    if document.cropRect != nil { CropCanvas(document: document) }
                    else { Canvas(document: document) }
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: NSColor(calibratedWhite: 0.09, alpha: 1)))
                    .overlay(alignment: .bottom) {
                        if let feedback {
                            Text(feedback).font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(.regularMaterial, in: Capsule())
                                .padding(16).allowsHitTesting(false)
                        }
                    }
                if document.cropRect != nil {
                    Text("Drag edges inward to crop or outward to extend in black. Applying merges annotations; Undo restores them.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(10)
                } else if noteExpanded { noteEditor }
            } else { welcome }
        }
        .frame(minWidth: 680, minHeight: 420)
        .background(.regularMaterial)
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: arrowOptions) { _, open in app.arrowLabelPopoverOpen = open }
        .onChange(of: document.status) { _, status in
            if ["Copied", "Saved", "No image", "Capture cancelled"].contains(where: status.hasPrefix) {
                feedback = status
            }
        }
        .task(id: feedback) {
            guard feedback != nil else { return }
            do { try await Task.sleep(for: .seconds(3)); feedback = nil } catch { }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 3) {
            if let rect = document.cropRect {
                Image(systemName: "crop").foregroundStyle(Color.accentColor).padding(.horizontal, 5)
                Text("\(Int((rect.width*document.pixelScale).rounded())) × \(Int((rect.height*document.pixelScale).rounded())) px")
                    .font(.system(size: 12)).monospacedDigit()
                Spacer()
                Button("Reset") { document.beginCrop() }.help("Reset to the current image bounds")
                Button("Cancel") { document.cropRect = nil }.help("Cancel crop · Escape")
                Button("Apply") { app.applyCrop() }.buttonStyle(.borderedProminent).help("Apply crop or extension · Return")
            } else {
            if document.image != nil {
                ForEach(Tool.allCases) { tool in
                    iconButton(tool.rawValue, symbol: tool.symbol, hint: "\(tool.rawValue) · \(tool.key) — \(tool.hint)", selected: document.tool == tool) {
                        app.finishText(); noteFocused = false
                        document.tool = tool; document.selected = nil
                    }
                    if tool == .text && (document.tool == .text || document.selectedMark?.tool == .text || document.editingText != nil) {
                        iconButton("Text background", symbol: "a.square.fill", hint: "Toggle black text background · ⌘⇧B", selected: document.activeTextBackground) {
                            document.setTextBackground(!document.activeTextBackground)
                        }.focusable(false)
                    }
                    if tool == .guide && (document.tool == .guide || document.selectedGuide != nil) { guideOptions }
                    if tool == .arrow && (document.tool == .arrow || document.selectedArrow != nil) {
                        arrowLabelMenu
                    }
                }
                iconButton("Crop / Extend", symbol: "crop", hint: "Crop or extend the image · C") {
                    app.finishText(); noteFocused = false; document.beginCrop()
                }
                separator
                Button { app.finishText(); colors.toggle() } label: {
                    Circle().fill(Color(nsColor: document.color)).frame(width: 15, height: 15)
                        .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
                        .frame(width: 30, height: 30)
                }.buttonStyle(.plain).help("Ink color · ⌘K").accessibilityLabel("Ink color").keyboardShortcut("k", modifiers: .command)
                    .popover(isPresented: $colors) { colorPanel }
                Menu {
                    ForEach(document.sizeChoices, id: \.self) { size in
                        Button("\(Int(size)) pt") { document.setSize(size) }
                            .help("Set \(document.adjustingTextSize ? "text size" : "stroke width") to \(Int(size)) points")
                    }
                } label: {
                    Text("\(Int(document.activeSize))")
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                }.menuStyle(.borderlessButton).fixedSize().frame(width: 40)
                    .help("\(document.adjustingTextSize ? "Text size" : "Stroke width") · [ smaller · ] larger")
                separator
                iconButton("Undo", symbol: "arrow.uturn.backward", hint: "Undo · ⌘Z") { app.finishText(); document.undo() }
                    .disabled(!document.canUndo)
                iconButton("Redo", symbol: "arrow.uturn.forward", hint: "Redo · ⌘⇧Z") { document.redo() }
                    .disabled(!document.canRedo)
            } else {
                Text("SnapNote").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            }
            Spacer(minLength: 8)
            if document.image != nil {
                iconButton("Note", symbol: document.blurb.isEmpty ? "text.bubble" : "text.bubble.fill", hint: "Show or hide footer note · ⌘⇧N", selected: noteExpanded) {
                    app.finishText(); noteExpanded.toggle(); noteFocused = noteExpanded
                }.keyboardShortcut("n", modifiers: [.command, .shift])
                separator
            }
            iconButton("Save", symbol: "square.and.arrow.down", hint: "Save PNG · ⌘S") { app.save() }
                .disabled(document.image == nil).keyboardShortcut("s")
            iconButton("More", symbol: "ellipsis", hint: "Settings and keyboard shortcuts · ⌘,") { app.finishText(); settings.toggle() }
                .popover(isPresented: $settings) { settingsPanel }.keyboardShortcut(",", modifiers: .command)
            Button { app.copyImage() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "doc.on.doc").font(.system(size: 11))
                    Text("Copy").font(.system(size: 12, weight: .semibold))
                }.padding(.horizontal, 11).frame(height: 28)
                    .foregroundStyle(.white).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain).disabled(document.image == nil)
                .accessibilityLabel("Copy image").help("Copy image and footer · ⌘⇧C")
                .keyboardShortcut("c", modifiers: [.command, .shift]).padding(.leading, 5)
            }
        }
        .padding(.leading, 78).padding(.trailing, 10).frame(height: 46)
    }

    private var guideOptions: some View {
        let axis = document.selectedGuide?.guideAxis ?? document.guideAxis
        let percent = document.selectedGuide?.showsPercentage ?? document.guidePercentage
        return HStack(spacing: 0) {
            Menu {
                ForEach(GuideAxis.allCases, id: \.self) { value in
                    Button(value.rawValue) { document.setGuideAxis(value) }
                        .help(value == .vertical ? "Vertical guide · 0% left, 100% right" : "Horizontal guide · 0% top, 100% bottom")
                }
            } label: { Text(axis == .vertical ? "V" : "H").font(.system(size: 11, weight: .medium)) }
                .menuStyle(.borderlessButton).fixedSize().frame(width: 32)
                .accessibilityLabel("Guide direction: \(axis.rawValue)").help("Guide direction · Shift+G")
            iconButton("Guide percentage", symbol: "percent", hint: "Show or hide guide percentage · ⌘⇧P", selected: percent) {
                document.setGuidePercentage(!percent)
            }.keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }

    private var arrowLabelMenu: some View {
        let label = document.selectedArrow?.text ?? document.arrowLabel
        let title = label.isEmpty ? "No label" : label
        return Button {
            app.finishText(); noteFocused = false; arrowOptions.toggle()
        } label: {
            HStack(spacing: 3) {
                Text(title).lineLimit(1).truncationMode(.tail).frame(maxWidth: 120)
                Image(systemName: "chevron.down").font(.system(size: 8))
            }.font(.system(size: 11, weight: .medium)).padding(.horizontal, 5).frame(height: 30)
        }.buttonStyle(.plain).fixedSize()
            .accessibilityLabel("Arrow label: \(title)").help("Arrow label and label size · ⌘⇧L").keyboardShortcut("l", modifiers: [.command, .shift])
            .popover(isPresented: $arrowOptions) { arrowPanel }
    }

    private var separator: some View { Divider().frame(height: 16).padding(.horizontal, 5).opacity(0.5) }

    private func iconButton(_ label: String, symbol: String, hint: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                .frame(width: 29, height: 30)
                .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.75))
                .background(selected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(hint).accessibilityLabel(label)
    }

    private var noteEditor: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.alignleft").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 9)
                // The hidden text measures wrapped lines; the editor scrolls beyond five.
                Text(document.blurb + "\u{200B}")
                    .font(.system(size: 13))
                    .lineLimit(1...5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hidden()
                    .accessibilityHidden(true)
                    .overlay {
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $document.blurb)
                                .font(.system(size: 13))
                                .scrollContentBackground(.hidden)
                                .focused($noteFocused)
                                .accessibilityLabel("Footer blurb").help("Text included below the image · Return: new line · ⌘⇧N: hide note")
                            if document.blurb.isEmpty {
                                Text("Add context… included below the exported image")
                                    .font(.system(size: 13)).foregroundStyle(.tertiary)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                iconButton("Collapse note", symbol: "chevron.down", hint: "Hide note · ⌘⇧N · Text stays in your export") {
                    noteFocused = false; noteExpanded = false
                }
            }.padding(.horizontal, 14).padding(.vertical, 8)
        }
    }

    private var arrowPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Arrow label").font(.system(size: 12, weight: .semibold))
            ForEach([""] + Document.arrowPresets, id: \.self) { label in
                Button {
                    document.setArrowLabel(label)
                    arrowOptions = false
                } label: {
                    HStack {
                        Text(label.isEmpty ? "No label" : label)
                        Spacer()
                        if (document.selectedArrow?.text ?? document.arrowLabel) == label {
                            Image(systemName: "checkmark")
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.vertical, 3)
                    .help(label.isEmpty ? "Remove the arrow label" : "Use \(label) as the arrow label")
            }
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Text("Custom label").font(.system(size: 12, weight: .semibold))
                ArrowLabelField(text: $customArrowLabel, onSubmit: applyCustomArrowLabel)
                    .frame(height: min(100, max(24, CGFloat(customArrowLabel.components(separatedBy: "\n").count) * 17 + 8)))
                Text("Shift+Return: new line · Return: apply")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Apply") { applyCustomArrowLabel() }
                        .buttonStyle(.borderedProminent).controlSize(.small).help("Apply custom label · Return")
                        .disabled(customArrowLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Divider()
            HStack {
                Text("Label size").font(.system(size: 12, weight: .semibold))
                Spacer()
                Menu("\(Int(document.selectedArrow?.fontSize ?? document.arrowFontSize)) pt") {
                    ForEach([12, 16, 20, 24, 32], id: \.self) { size in
                        Button("\(size) pt") { document.setArrowFontSize(CGFloat(size)) }.help("Set arrow label text to \(size) points")
                    }
                }.fixedSize().accessibilityLabel("Arrow label size").help("Change arrow label text size")
            }
            Toggle("Black background", isOn: Binding(get: { document.activeArrowTextBackground }, set: { document.setArrowTextBackground($0) }))
                .toggleStyle(.switch).controlSize(.small)
                .help("Black background behind the arrow label · ⌘⇧B")
            Text("Drag square handles to resize the arrow. Drag the round handle to curve it.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(width: 230)
            .onAppear {
                let current = document.selectedArrow?.text ?? document.arrowLabel
                customArrowLabel = Document.arrowPresets.contains(current) ? "" : current
            }

    }

    private func applyCustomArrowLabel() {
        let label = customArrowLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }
        document.setArrowLabel(label)
        arrowOptions = false
    }

    private var colorPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ink color").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 9) {
                ForEach(palette, id: \.0) { name, color in
                    Button { setColor(color); colors = false } label: {
                        Circle().fill(Color(nsColor: color)).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(.gray.opacity(0.5), lineWidth: 1))
                            .padding(3).overlay(Circle().stroke(document.color == color ? Color.accentColor : .clear, lineWidth: 2))
                    }.buttonStyle(.plain).help("Use \(name.lowercased()) ink").accessibilityLabel("\(name) ink")
                }
            }
            ColorPicker("Custom color", selection: Binding(get: { Color(nsColor: document.color) }, set: { setColor(NSColor($0)) }), supportsOpacity: false).help("Choose any ink color")
        }.padding(16)
    }

    private func setColor(_ color: NSColor) {
        document.color = color
        if let id = document.selected {
            document.commit(document.marks.map { mark in var m = mark; if m.id == id { m.color = color }; return m })
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "viewfinder").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(.secondary)
            Text("Capture something.").font(.system(size: 23, weight: .medium))
            Button { app.capture() } label: { Text("Select an area   ⌘⇧2").padding(.horizontal, 12).padding(.vertical, 5) }
                .buttonStyle(.borderedProminent).help("Capture a rectangular area · ⌘⇧2")
            HStack(spacing: 20) {
                Button("Open image…") { app.openImage() }.help("Open an image file · ⌘O")
                Button("Try a sample") { document.load(Sample.image()) }.help("Open a sample image to try the annotation tools")
            }.buttonStyle(.link).font(.system(size: 12))
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SnapNote").font(.headline)
            Button("Open image…   ⌘O") { settings = false; app.openImage() }.help("Open an image file · ⌘O")
            Button("Paste image   ⌘V") { settings = false; app.pasteImage() }.help("Open the image on the clipboard · ⌘V")
            Divider()
            Toggle("Launch at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { enabled in
                do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { app.showError(error.localizedDescription) }
            })).help("Start SnapNote automatically when you sign in")
            Button("Screen capture permissions…") { app.openPermissions() }.help("Open macOS screen recording permissions for SnapNote")
            Text("⌘⇧2 captures anywhere. Closing this window keeps the shortcut active.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            Text(Tool.allCases.map { "\($0.key) \($0.rawValue)" }.joined(separator: " · "))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            Text("⌘K Color · ⌘⇧L Labels · ⌘⇧N Note\n[ / ] Size · Delete Remove · Esc Cancel")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Button("Quit SnapNote") { NSApp.terminate(nil) }.help("Quit SnapNote · ⌘Q")
        }.padding(18).frame(width: 290)
    }
}

enum Sample {
    static func image() -> NSImage {
        let image = NSImage(size: CGSize(width: 1000, height: 560))
        image.lockFocusFlipped(true)
        NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill(); CGRect(x: 0, y: 0, width: 1000, height: 560).fill()
        func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ color: NSColor = .black, _ weight: NSFont.Weight = .regular) {
            (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        }
        text("FIELDNOTES", 50, 38, 14, .darkGray, .bold)
        text("Make room for the good ideas.", 50, 110, 39, .black, .semibold)
        text("A quiet place to collect what catches your eye.", 50, 173, 19, .darkGray)
        for (i, title) in ["Collect", "Connect", "Create"].enumerated() {
            let x = CGFloat(50+i*310)
            NSColor.white.setFill(); NSBezierPath(roundedRect: CGRect(x: x,y: 255,width: 285,height: 180), xRadius: 12,yRadius: 12).fill()
            text("0\(i+1)", x+24, 278, 13, .systemOrange, .semibold)
            text(title, x+24, 316, 25, .black, .semibold)
            text(["Save a little inspiration.", "Find the common thread.", "Turn it into something."][i], x+24, 365, 15, .darkGray)
        }
        NSColor(calibratedRed: 0.18, green: 0.32, blue: 0.26, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: 50,y: 477,width: 185,height: 44),xRadius: 8,yRadius: 8).fill()
        text("Start a collection →", 69, 488, 15, .white, .medium)
        image.unlockFocus()
        return image
    }
}
