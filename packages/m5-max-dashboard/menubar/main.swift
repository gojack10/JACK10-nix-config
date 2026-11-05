import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let titleView = StatusTitleView(frame: .zero)
    private let popover = NSPopover()
    private let model = DashboardModel()
    private let gpu = GPUReader()
    private let queue = DispatchQueue(label: "m5-max-dashboard.metrics", qos: .utility)
    private var timer: Timer?
    private var sampling = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 0)
        statusItem.autosaveName = "M5 Max Dashboard"
        titleView.install(in: statusItem)
        if let button = statusItem.button {
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
        if full { gpu.refresh() }
        let readings = gpu.sample()
        sampling = true
        queue.async { [weak self] in
            let result = Result { try Snapshot(full: full, shaderCores: readings.cores, bandwidth: readings.bandwidth) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.sampling = false
                switch result {
                case .success(let snapshot):
                    self.statusItem.button?.setAccessibilityValue(self.titleView.update(snapshot))
                    self.statusItem.button?.toolTip = "M5 Max Dashboard - sampled \(snapshot.sampledAt.formatted(date: .omitted, time: .standard))"
                    self.model.error = nil
                    if full { self.model.snapshot = snapshot }
                case .failure(let error):
                    _ = self.titleView.update(nil)
                    self.statusItem.button?.setAccessibilityValue("System stats unavailable")
                    self.statusItem.button?.toolTip = "M5 Max Dashboard - \(error.localizedDescription)"
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
