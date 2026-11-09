import AppKit

// Native vibrant-dark menu white, matching the supplied weather reference.
private let statusTextColor = NSColor(white: 1, alpha: 229.0 / 255.0)

func batteryWarningColor(_ percent: Double?, lowPowerMode: Bool) -> NSColor? {
    if let percent, percent <= 10 { return .systemRed }
    if lowPowerMode || (percent ?? 100) <= 25 { return .systemYellow }
    return nil
}

private final class StatusMetricView: NSStackView {
    private let value = NSTextField(labelWithString: "-")
    private let unit: String

    init(label: String, unit: String, capacity: String) {
        self.unit = unit
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .firstBaseline
        spacing = 1
        setAccessibilityElement(false)

        let font = NSFont.systemFont(ofSize: 13, weight: .regular)
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        if !label.isEmpty {
            let name = NSTextField(labelWithString: label)
            name.font = font
            name.textColor = statusTextColor
            name.setAccessibilityElement(false)
            addArrangedSubview(name)
            setCustomSpacing(3, after: name)
        }

        value.font = numberFont
        value.stringValue = "-" + unit
        value.textColor = statusTextColor
        value.alignment = .right
        value.lineBreakMode = .byClipping
        value.setAccessibilityElement(false)
        addArrangedSubview(value)
        // One text run keeps the unit attached, without a second field's inset.
        // Right alignment pins the unit and decimal even when digit counts change.
        let width = ceil(((capacity + unit) as NSString).size(withAttributes: [.font: numberFont]).width) + 4
        value.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ text: String, color: NSColor = statusTextColor) {
        value.stringValue = text + unit
        value.textColor = color
    }
}

// Native fields inside the status button: fixed slots, no title-string reflow.
final class StatusTitleView: NSStackView {
    private let cpu = StatusMetricView(label: "CPU", unit: "%", capacity: "000")
    private let memory = StatusMetricView(label: "MEM", unit: "GiB", capacity: "0000.0")
    private let battery = StatusMetricView(label: "BAT", unit: "%", capacity: "000")
    private let power = StatusMetricView(label: "", unit: "W", capacity: "+000.0")

    override init(frame: NSRect) {
        super.init(frame: frame)
        orientation = .horizontal
        alignment = .firstBaseline
        spacing = 10
        setAccessibilityElement(false)
        // Watts grows left into the outside margin, not into a gap between metrics.
        for metric in [power, battery, cpu, memory] { addArrangedSubview(metric) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Preserve the native button's click, highlight and Command-drag behavior.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func install(in item: NSStatusItem) {
        guard let button = item.button else { return }
        let size = fittingSize
        item.length = ceil(size.width) + 12
        button.title = ""
        button.setAccessibilityLabel("M5 Max Dashboard")
        translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: button.centerXAnchor),
            centerYAnchor.constraint(equalTo: button.centerYAnchor),
            widthAnchor.constraint(equalToConstant: ceil(size.width)),
            heightAnchor.constraint(equalToConstant: ceil(size.height)),
        ])
    }

    func update(_ snapshot: Snapshot?, lowPowerMode: Bool) -> String {
        let cpuText = fixed(snapshot?.number("cpu.utilization"), places: 0)
        let memoryText = fixed(snapshot?.number("memory.in_use_gb"))
        let batteryPercent = snapshot?.number("power.battery_pct")
        let batteryText = fixed(batteryPercent, places: 0)
        let watts = snapshot?.number("power.net_watts")
        let powerText = watts.map { String(format: "%+.1f", $0) } ?? "-"

        cpu.update(cpuText)
        memory.update(memoryText)
        let batteryColor = batteryWarningColor(batteryPercent, lowPowerMode: lowPowerMode) ?? statusTextColor
        battery.update(batteryText, color: batteryColor)
        let powerColor: NSColor = (batteryPercent ?? 100) < 15 ? .systemRed
            : (watts ?? 0) > 0.5 ? .systemGreen
            : (watts ?? 0) < -0.5 ? .systemOrange : statusTextColor
        power.update(powerText, color: powerColor)
        let mode = lowPowerMode ? ", Low Power Mode on" : ""
        return "Net power \(powerText) watts, battery \(batteryText)%\(mode), CPU \(cpuText)%, memory \(memoryText) GiB"
    }
}
