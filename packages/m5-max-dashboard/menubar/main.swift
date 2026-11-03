import AppKit

private let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

private func color(_ tone: Tone) -> NSColor {
    switch tone {
    case .success: return .green
    case .warning: return .yellow
    case .urgent: return .red
    case .plain, .heading: return .white
    }
}

private func attributed(_ rows: [Row], size: CGFloat = 11) -> NSAttributedString {
    let result = NSMutableAttributedString(string: "")
    let paragraph = NSMutableParagraphStyle()
    paragraph.minimumLineHeight = 16
    paragraph.maximumLineHeight = 16
    paragraph.lineBreakMode = .byClipping
    for (index, row) in rows.enumerated() {
        for piece in row {
            let face = NSFont.monospacedSystemFont(ofSize: size, weight: piece.tone == .heading ? .semibold : .regular)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: face,
                .foregroundColor: piece.inverted ? NSColor.black : color(piece.tone),
                .backgroundColor: piece.inverted ? color(piece.tone) : NSColor.black,
                .paragraphStyle: paragraph,
            ]
            result.append(NSAttributedString(string: piece.text, attributes: attributes))
        }
        if index != rows.count - 1 { result.append(NSAttributedString(string: "\n")) }
    }
    return result
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let textView = NSTextView()
    private let scroll = NSScrollView()
    private let queue = DispatchQueue(label: "m5-max-dashboard.metrics", qos: .utility)
    private var timer: Timer?
    private var sampling = false
    private var lastSample = Date.distantPast
    private var lastDashboard: [Row] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "M5 Max Dashboard"
        if let button = statusItem.button {
            button.attributedTitle = attributed([[Piece(text: "CPU   -% | GPU   -% | MEM   -%")]], size: 10)
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.black.cgColor
            button.target = self
            button.action = #selector(toggle)
            button.toolTip = "M5 Max Dashboard - click for all system stats"
        }
        configurePopover()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        sample()
    }

    private func configurePopover() {
        let controller = NSViewController()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 740))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        controller.view = root
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.backgroundColor = .black
        root.addSubview(scroll)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = font
        textView.textColor = .white
        textView.backgroundColor = .black
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 10000, height: CGFloat.greatestFiniteMagnitude)
        scroll.documentView = textView
        let footer = NSStackView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.orientation = .horizontal
        footer.spacing = 16
        for (title, action) in [("OPEN WEB", #selector(openWeb)), ("QUIT", #selector(quit))] {
            let button = NSButton(title: title, target: self, action: action)
            button.isBordered = false
            button.font = font
            button.contentTintColor = .white
            footer.addArrangedSubview(button)
        }
        root.addSubview(footer)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            footer.heightAnchor.constraint(equalToConstant: 24),
        ])
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        show([[Piece(text: "COLLECTING SYSTEM STATS", tone: .heading)]])
    }

    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        let available = button.window?.screen?.visibleFrame.height ?? 800
        popover.contentSize = NSSize(width: 720, height: min(740, max(240, available - 60)))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        sample(force: true)
    }

    private func sample(force: Bool = false) {
        guard !sampling else { return }
        let full = popover.isShown
        guard force || full || Date().timeIntervalSince(lastSample) >= 5 else { return }
        sampling = true
        queue.async { [weak self] in
            let result = Result { try Snapshot(full: full) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.sampling = false
                switch result {
                case .success(let snapshot):
                    self.lastSample = snapshot.sampledAt
                    self.statusItem.button?.attributedTitle = attributed([titlePieces(snapshot)], size: 10)
                    self.statusItem.button?.toolTip = "M5 Max Dashboard - sampled \(snapshot.sampledAt.formatted(date: .omitted, time: .standard))"
                    if full {
                        self.lastDashboard = dashboard(snapshot)
                        self.show(self.lastDashboard)
                    }
                case .failure(let error):
                    self.statusItem.button?.attributedTitle = attributed([[Piece(text: "M5 STATS UNAVAILABLE", tone: .urgent)]], size: 10)
                    self.show([[Piece(text: "READ FAILED - \(clean(error.localizedDescription))", tone: .urgent)], []]
                              + self.lastDashboard)
                }
            }
        }
    }

    private func show(_ rows: [Row]) {
        let origin = scroll.contentView.bounds.origin
        let content = attributed(rows)
        textView.textStorage?.setAttributedString(content)
        let width = max(680, ceil(content.size().width) + 32)
        textView.setFrameSize(NSSize(width: width, height: CGFloat(rows.count) * 16 + 24))
        scroll.contentView.scroll(to: origin)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    @objc private func openWeb() { NSWorkspace.shared.open(URL(string: "http://localhost:8765/")!) }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
