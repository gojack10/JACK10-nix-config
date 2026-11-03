import AppKit
import SwiftUI

private let menuFont = NSFont.monospacedDigitSystemFont(
    ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)

private func title(_ snapshot: Snapshot) -> NSAttributedString {
    let battery = snapshot.number("power.battery_pct")
    let watts = snapshot.number("power.net_watts")
    var fields: [(String, NSColor)] = [
        ("CPU " + fixed(snapshot.number("cpu.utilization"), places: 0) + "%", .labelColor),
        ("MEM " + fixed(snapshot.percent("memory.in_use_gb", of: "memory.total_gb"), places: 0) + "%", .labelColor),
    ]
    if let battery {
        fields.append(("BAT " + fixed(battery, places: 0) + "%",
                       battery <= 10 ? .systemRed : battery <= 25 ? .systemOrange : .labelColor))
    }
    if let watts {
        let external = snapshot.value("power.external_connected") as? Bool ?? false
        let color: NSColor = (battery ?? 100) < 15 ? .systemRed
            : !external ? .labelColor : watts > 0.5 ? .systemGreen : watts < -0.5 ? .systemOrange : .labelColor
        fields.append((String(format: "%+.1fW", watts), color))
    }
    let result = NSMutableAttributedString(string: "")
    for (index, field) in fields.enumerated() {
        if index > 0 {
            result.append(NSAttributedString(string: " | ", attributes: [.font: menuFont, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        result.append(NSAttributedString(string: field.0, attributes: [.font: menuFont, .foregroundColor: field.1]))
    }
    return result
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = DashboardModel()
    private let queue = DispatchQueue(label: "m5-max-dashboard.metrics", qos: .utility)
    private var timer: Timer?
    private var sampling = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "M5 Max Dashboard"
        if let button = statusItem.button {
            button.font = menuFont
            button.title = "CPU -% | MEM -%"
            button.target = self
            button.action = #selector(toggle)
            button.toolTip = "M5 Max Dashboard - click for all system stats"
        }
        popover.contentViewController = NSHostingController(rootView: DashboardView(
            model: model,
            openWeb: { NSWorkspace.shared.open(URL(string: "http://localhost:8765/")!) },
            quit: { NSApp.terminate(nil) }))
        popover.contentSize = NSSize(width: 640, height: 740)
        popover.behavior = .transient
        let clock = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(clock, forMode: .common)
        timer = clock
        sample()
    }

    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        let available = button.window?.screen?.visibleFrame.height ?? 800
        popover.contentSize = NSSize(width: 640, height: min(740, max(240, available - 60)))
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        sample()
    }

    private func sample() {
        guard !sampling else { return }
        let full = popover.isShown
        sampling = true
        queue.async { [weak self] in
            let result = Result { try Snapshot(full: full) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.sampling = false
                switch result {
                case .success(let snapshot):
                    self.statusItem.button?.attributedTitle = title(snapshot)
                    self.statusItem.button?.toolTip = "M5 Max Dashboard - sampled \(snapshot.sampledAt.formatted(date: .omitted, time: .standard))"
                    self.model.error = nil
                    if full { self.model.snapshot = snapshot }
                case .failure(let error):
                    self.statusItem.button?.title = "M5 Stats Unavailable"
                    self.model.error = error.localizedDescription
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
