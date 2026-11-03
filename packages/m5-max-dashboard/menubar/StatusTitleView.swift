import AppKit

private final class StatusMetricView: NSStackView {
    private let value = NSTextField(labelWithString: "-")

    init(label: String, unit: String, capacity: String) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .firstBaseline
        spacing = 1
        setAccessibilityElement(false)

        let font = NSFont.systemFont(ofSize: 12, weight: .regular)
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        if !label.isEmpty {
            let name = NSTextField(labelWithString: label)
            name.font = font
            name.textColor = .secondaryLabelColor
            name.setAccessibilityElement(false)
            addArrangedSubview(name)
            setCustomSpacing(3, after: name)
        }

        value.font = numberFont
        value.alignment = .right
        value.lineBreakMode = .byClipping
        value.setAccessibilityElement(false)
        addArrangedSubview(value)
        // Reserve the largest normal reading, not the current string's width.
        // A separate unit field also pins the percentage sign / watt suffix.
        let width = ceil((capacity as NSString).size(withAttributes: [.font: numberFont]).width) + 4
        value.widthAnchor.constraint(equalToConstant: width).isActive = true

        let suffix = NSTextField(labelWithString: unit)
        suffix.font = font
        suffix.textColor = .secondaryLabelColor
        suffix.setAccessibilityElement(false)
        addArrangedSubview(suffix)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ text: String, color: NSColor = .labelColor) {
        value.stringValue = text
        value.textColor = color
    }
}

// Native fields inside the status button: fixed slots, no title-string reflow.
final class StatusTitleView: NSStackView {
    private let cpu = StatusMetricView(label: "CPU", unit: "%", capacity: "000")
    private let memory = StatusMetricView(label: "Mem", unit: "%", capacity: "000")
    private let battery = StatusMetricView(label: "Bat", unit: "%", capacity: "000")
    private let power = StatusMetricView(label: "", unit: "W", capacity: "+000.0")

    override init(frame: NSRect) {
        super.init(frame: frame)
        orientation = .horizontal
        alignment = .firstBaseline
        spacing = 10
        setAccessibilityElement(false)
        for metric in [cpu, memory, battery, power] { addArrangedSubview(metric) }
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

    func update(_ snapshot: Snapshot?) -> String {
        let cpuText = fixed(snapshot?.number("cpu.utilization"), places: 0)
        let memoryText = fixed(snapshot?.percent("memory.in_use_gb", of: "memory.total_gb"), places: 0)
        let batteryPercent = snapshot?.number("power.battery_pct")
        let batteryText = fixed(batteryPercent, places: 0)
        let watts = snapshot?.number("power.net_watts")
        let powerText = watts.map { String(format: "%+.1f", $0) } ?? "-"

        cpu.update(cpuText)
        memory.update(memoryText)
        battery.update(batteryText, color: (batteryPercent ?? 100) <= 10 ? .systemRed
            : (batteryPercent ?? 100) <= 25 ? .systemOrange : .labelColor)
        let external = snapshot?.value("power.external_connected") as? Bool ?? false
        let powerColor: NSColor = (batteryPercent ?? 100) < 15 ? .systemRed
            : !external ? .labelColor : (watts ?? 0) > 0.5 ? .systemGreen
            : (watts ?? 0) < -0.5 ? .systemOrange : .labelColor
        power.update(powerText, color: powerColor)
        return "CPU \(cpuText)%, memory \(memoryText)%, battery \(batteryText)%, net power \(powerText) watts"
    }
}
