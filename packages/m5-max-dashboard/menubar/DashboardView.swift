import AppKit
import SwiftUI

final class DashboardModel: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var error: String?
}

private enum MetricColumns {
    static let label: CGFloat = 128
    static let bar: CGFloat = 118
    static let value: CGFloat = 76
    static let unit: CGFloat = 36
    static let gap: CGFloat = 12
}

// Presentation thresholds, not hardware-specific throttling limits.
private func temperatureColor(_ value: Double?) -> Color {
    guard let value, value.isFinite else { return .secondary }
    return Color(nsColor: value < 70 ? .systemGreen : value < 85 ? .systemOrange : .systemRed)
}

private struct CapacityIndicator: NSViewRepresentable {
    let label: String
    let value: Double?
    var battery = false
    var neutral = false

    func makeNSView(context: Context) -> NSLevelIndicator {
        let indicator = NSLevelIndicator(frame: .zero)
        indicator.levelIndicatorStyle = .continuousCapacity
        indicator.controlSize = .small
        indicator.isEditable = false
        indicator.minValue = 0
        indicator.maxValue = 100
        indicator.warningValue = 50
        indicator.criticalValue = 80
        indicator.drawsTieredCapacityLevels = false
        return indicator
    }

    func updateNSView(_ indicator: NSLevelIndicator, context: Context) {
        indicator.doubleValue = min(100, max(0, value ?? 0))
        indicator.isEnabled = value != nil
        if neutral || battery {
            let color: NSColor = neutral ? .systemBlue
                : (value ?? 100) <= 10 ? .systemRed : (value ?? 100) <= 25 ? .systemYellow : .systemGreen
            indicator.fillColor = color
            indicator.warningFillColor = color
            indicator.criticalFillColor = color
        } else {
            indicator.fillColor = .systemGreen
            indicator.warningFillColor = .systemYellow
            indicator.criticalFillColor = .systemRed
        }
        indicator.setAccessibilityLabel(value == nil ? "\(label) - unavailable" : label)
    }
}

private struct MetricLabel: View {
    let text: String
    var child = false

    var body: some View {
        Text(text)
            .foregroundStyle(child ? .secondary : .primary)
            .padding(.leading, child ? 12 : 0)
            .frame(width: MetricColumns.label, alignment: .leading)
    }
}

private struct MetricValue: View {
    let value: String
    var unit = ""

    var body: some View {
        HStack(spacing: MetricColumns.gap) {
            Text(value).frame(width: MetricColumns.value, alignment: .trailing)
            Text(unit).foregroundStyle(.secondary).frame(width: MetricColumns.unit, alignment: .leading)
        }
        .monospacedDigit()
    }
}

private struct MetricRow: View {
    let label: String
    let value: String
    var unit = ""
    var share = ""
    var percent: Double? = nil
    var bar = false
    var child = false
    var neutral = false

    var body: some View {
        HStack(spacing: MetricColumns.gap) {
            MetricLabel(text: label, child: child)
            if bar {
                CapacityIndicator(label: label, value: percent, neutral: neutral)
                    .frame(width: MetricColumns.bar, height: 12)
            } else {
                Color.clear.frame(width: MetricColumns.bar, height: 1).accessibilityHidden(true)
            }
            MetricValue(value: value, unit: unit)
            Text(share).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 48, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 18)
    }
}

// Tables use the same first numeric anchor as metric rows, including empty bar space.
private struct NumericTableRow: View {
    let label: String
    let values: [String]
    var colors: [Color] = []

    var body: some View {
        HStack(spacing: MetricColumns.gap) {
            MetricLabel(text: label)
            Color.clear.frame(width: MetricColumns.bar, height: 1).accessibilityHidden(true)
            ForEach(values.indices, id: \.self) { index in
                Text(values[index]).monospacedDigit()
                    .foregroundStyle(index < colors.count ? colors[index] : .primary)
                    .frame(width: MetricColumns.value, alignment: .trailing)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 18)
    }
}

private struct CoreMeter: View {
    let core: CoreReading

    var body: some View {
        HStack(spacing: 6) {
            Text(String(core.id)).frame(width: 18, alignment: .trailing)
            CapacityIndicator(label: "Core \(core.id)", value: core.percent)
                .frame(maxWidth: .infinity).frame(height: 10)
            Text(fixed(core.percent, places: 0, suffix: "%"))
                .frame(width: 36, alignment: .trailing)
        }
        .font(.system(size: 11)).monospacedDigit()
        .frame(maxWidth: .infinity).frame(height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Core \(core.id), \(core.percent.map { fixed($0, places: 0) + " percent" } ?? "unavailable")")
    }
}

private struct CoreMeters: View {
    let title: String
    let group: CoreGroup

    var body: some View {
        MetricSection(title) {
            if !group.summaries.isEmpty {
                HStack(spacing: 16) {
                    ForEach(group.summaries.indices, id: \.self) { index in
                        let summary = group.summaries[index]
                        HStack(spacing: 4) {
                            Text(summary.label)
                            Spacer(minLength: 4)
                            Text(summary.value).frame(width: 48, alignment: .trailing)
                            Text(summary.unit).frame(width: 10, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 16,
                                                         alignment: .leading),
                                     count: max(1, group.columns.count)),
                      alignment: .leading, spacing: 3) {
                ForEach(group.columns.indices, id: \.self) { index in
                    Text(group.columns[index].title).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(0..<group.rowCount, id: \.self) { row in
                    ForEach(group.columns.indices, id: \.self) { index in
                        let column = group.columns[index]
                        if row < column.cores.count {
                            CoreMeter(core: column.cores[row])
                        } else {
                            Color.clear.frame(height: 18).accessibilityHidden(true)
                        }
                    }
                }
            }
            if let status = group.status {
                Text(status).font(.caption).foregroundStyle(.orange)
            }
        }
        .help(group.detail)
    }
}

private struct MetricSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

struct DashboardView: View {
    @ObservedObject var model: DashboardModel
    let openWeb: () -> Void
    let quit: () -> Void
    @State private var copyFeedback = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(16)
            Divider()
            ScrollView {
                if let s = model.snapshot {
                    VStack(alignment: .leading, spacing: 10) {
                        cpu(s)
                        CoreMeters(title: "CPU cores", group: .cpu(s))
                        processes(s)
                        Divider()
                        gpu(s)
                        CoreMeters(title: "GPU shader throughput | % peak", group: .gpu(s.shaderCores))
                        Divider()
                        memory(s)
                        Divider()
                        swap(s)
                        Divider()
                        MetricSection("Pressure") {
                            Text(s.text("memory_pressure"))
                                .foregroundStyle(s.text("memory_pressure") == "OK" ? Color(nsColor: .systemGreen)
                                    : s.text("memory_pressure") == "CRITICAL" ? Color(nsColor: .systemRed)
                                    : s.text("memory_pressure") == "MODERATE" ? Color(nsColor: .systemYellow) : .primary)
                        }
                        Divider()
                        thermals(s)
                        Divider()
                        fans(s)
                        Divider()
                        power(s)
                    }
                    .padding(16)
                } else if let error = model.error {
                    Text("Unavailable").foregroundStyle(.red).help(clean(error))
                        .frame(maxWidth: .infinity).padding(32)
                } else {
                    ProgressView("Collecting system stats")
                        .frame(maxWidth: .infinity).padding(32)
                }
            }
            Divider()
            HStack {
                Button(action: copyAllStats) {
                    Label("Copy All Stats", systemImage: "doc.on.doc")
                }
                .disabled(model.snapshot == nil)
                .help("Copy all sections as aligned text")
                Button("Open Web", action: openWeb)
                Text(copyFeedback).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit", action: quit)
            }
            .controlSize(.small)
            .padding(12)
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func copyAllStats() {
        guard let snapshot = model.snapshot else { return }
        var text = dashboard(snapshot).map { $0.map(\.text).joined() }.joined(separator: "\n") + "\n"
        if model.error != nil { text = "STALE SNAPSHOT\n\n" + text }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        copyFeedback = pasteboard.setString(text, forType: .string) ? "Copied" : "Copy failed"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("M5 Max").font(.title3.weight(.semibold))
                if let s = model.snapshot {
                    Text(s.text("cpu.model")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(s.sampledAt.formatted(date: .omitted, time: .standard)).font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let s = model.snapshot {
                HStack {
                    Text("Uptime \(s.uptime)").monospacedDigit()
                    if let error = model.error {
                        Spacer()
                        Text("Stale").foregroundStyle(.red).help(clean(error))
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func gpu(_ s: Snapshot) -> some View {
        let bandwidth = s.bandwidth
        return MetricSection("GPU | \(fixed(s.number("gpu.core_count"), places: 0)) cores") {
            MetricRow(label: "Utilization", value: fixed(s.number("gpu.utilization"), places: 0), unit: "%",
                      percent: s.number("gpu.utilization"), bar: true)
            MetricRow(label: "Renderer", value: fixed(s.number("gpu.renderer_util"), places: 0), unit: "%")
            MetricRow(label: "Tiler", value: fixed(s.number("gpu.tiler_util"), places: 0), unit: "%")
            MetricRow(label: "Shared memory", value: fixed(s.number("memory.total_gb"), places: 0), unit: "GiB")
            MetricRow(label: "Allocated", value: fixed(s.number("gpu.alloc_sys_mem_gb")), unit: "GiB",
                      share: fixed(s.percent("gpu.alloc_sys_mem_gb", of: "memory.total_gb"), places: 0, suffix: "%"),
                      percent: s.percent("gpu.alloc_sys_mem_gb", of: "memory.total_gb"), bar: true)
            MetricRow(label: "In use", value: fixed(s.number("gpu.in_use_sys_mem_gb")), unit: "GiB",
                      share: fixed(s.percent("gpu.in_use_sys_mem_gb", of: "memory.total_gb"), places: 0, suffix: "%"),
                      percent: s.percent("gpu.in_use_sys_mem_gb", of: "memory.total_gb"), bar: true)
            MetricRow(label: "Read bandwidth", value: fixed(bandwidth.read), unit: "GB/s",
                      percent: bandwidth.read.map { $0 * 100 / bandwidth.scale }, bar: true, neutral: true)
            MetricRow(label: "Write bandwidth", value: fixed(bandwidth.write), unit: "GB/s",
                      percent: bandwidth.write.map { $0 * 100 / bandwidth.scale }, bar: true, neutral: true)
            HStack {
                Text("Bandwidth scale | 0-\(fixed(bandwidth.scale, places: 0)) GB/s")
                Spacer()
                if bandwidth.status != "Live" {
                    Text(bandwidth.status).foregroundStyle(.orange)
                }
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            .help("GPU-attributed memory-controller traffic, not whole-system DRAM. Chart range is not hardware capacity. \(bandwidth.detail)")
        }
        .help(clean(s.text("gpu.model")))
    }

    private func cpu(_ s: Snapshot) -> some View {
        MetricSection("CPU | \(fixed(s.number("cpu.count"), places: 0)) cores") {
            MetricRow(label: "Utilization", value: fixed(s.number("cpu.utilization"), places: 0), unit: "%",
                      percent: s.number("cpu.utilization"), bar: true)
                .help("% time busy since previous sample")
            MetricRow(label: "Load 1m", value: fixed(s.number("cpu.load_avg"), places: 2))
        }
    }

    private func memory(_ s: Snapshot) -> some View {
        MetricSection("Memory | \(fixed(s.number("memory.total_gb"), places: 0)) GiB") {
            MetricRow(label: "In use", value: fixed(s.number("memory.in_use_gb")), unit: "GiB",
                      share: fixed(s.percent("memory.in_use_gb", of: "memory.total_gb"), places: 0, suffix: "%"),
                      percent: s.percent("memory.in_use_gb", of: "memory.total_gb"), bar: true)
            MetricRow(label: "Free", value: fixed(s.number("memory.free_gb")), unit: "GiB")
            MetricRow(label: "Active", value: fixed(s.number("memory.active_gb")), unit: "GiB")
            MetricRow(label: "Wired", value: fixed(s.number("memory.wired_gb")), unit: "GiB")
            MetricRow(label: "Kernel (est.)", value: fixed(s.number("memory.wired_context.kernel_baseline_gb")), unit: "GiB", child: true)
            MetricRow(label: "Other wired (est.)", value: fixed(s.number("memory.wired_context.other_wired_estimate_gb")), unit: "GiB", child: true)
            MetricRow(label: "Inactive", value: fixed(s.number("memory.inactive_gb")), unit: "GiB")
            MetricRow(label: "Speculative", value: fixed(s.number("memory.speculative_gb")), unit: "GiB")
            MetricRow(label: "Purgeable", value: fixed(s.number("memory.purgeable_gb")), unit: "GiB")
            MetricRow(label: "Compressor", value: fixed(s.number("memory.compressor_gb")), unit: "GiB")
            MetricRow(label: "Reclaimable (est.)", value: fixed(s.number("memory.reclaimable_gb")), unit: "GiB")
        }
    }

    private func swap(_ s: Snapshot) -> some View {
        MetricSection("Swap | \(fixed(s.number("swap.total_mb"), places: 0)) MiB") {
            MetricRow(label: "Used", value: fixed(s.number("swap.used_mb"), places: 0), unit: "MiB",
                      share: fixed(s.percent("swap.used_mb", of: "swap.total_mb"), places: 0, suffix: "%"),
                      percent: s.percent("swap.used_mb", of: "swap.total_mb"), bar: true)
        }
    }

    private func thermals(_ s: Snapshot) -> some View {
        MetricSection("Thermals | °C | peaks since launch") {
            NumericTableRow(label: "Sensor", values: ["Current", "Peak", "Sensors"])
                .font(.caption).foregroundStyle(.secondary)
            ForEach(["cpu", "gpu", "mem", "soc"], id: \.self) { key in
                let current = s.number(key == "soc" ? "thermals.soc" : "thermals.\(key)_max")
                let peak = s.number("thermals.\(key)_peak")
                let count = key == "soc" ? (current == nil ? "-" : "1")
                    : fixed(s.number("thermals.\(key)_count"), places: 0)
                NumericTableRow(label: key == "mem" ? "Memory" : key == "soc" ? "SoC" : key.uppercased(),
                                values: [fixed(current), fixed(peak), count],
                                colors: [temperatureColor(current), temperatureColor(peak), .primary])
            }
        }
        .help("Current is the hottest available sensor. Peaks are observed since app launch.")
    }

    private func fans(_ s: Snapshot) -> some View {
        MetricSection("Fans | \(Int(s.number("fans.count") ?? 0))") {
            NumericTableRow(label: "Fan", values: ["RPM", "Min", "Max"])
                .font(.caption).foregroundStyle(.secondary)
            ForEach(0..<Int(s.number("fans.count") ?? 0), id: \.self) { i in
                NumericTableRow(label: "F\(i)", values: [fixed(s.number("fans.F\(i).rpm"), places: 0),
                                                       fixed(s.number("fans.F\(i).min"), places: 0),
                                                       fixed(s.number("fans.F\(i).max"), places: 0)])
            }
        }
    }

    private func processes(_ s: Snapshot) -> some View {
        let rows = s.value("cpu.top") as? [[String: Any]] ?? []
        return MetricSection("Top CPU") {
            HStack(spacing: 20) {
                Text("PID").frame(width: 64, alignment: .trailing)
                Text("CPU %").frame(width: 64, alignment: .trailing)
                Text("Process").frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption).foregroundStyle(.secondary)
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 20) {
                    Text((rows[i]["pid"] as? NSNumber)?.stringValue ?? "-").frame(width: 64, alignment: .trailing)
                    Text(fixed((rows[i]["cpu"] as? NSNumber)?.doubleValue)).frame(width: 64, alignment: .trailing)
                    Text(clean(rows[i]["name"] as? String ?? "-")).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(clean(rows[i]["name"] as? String ?? "-"))
                }.monospacedDigit()
            }
        }
        .help("ps %CPU")
    }

    private func battery(_ s: Snapshot) -> some View {
        let percent = s.number("power.battery_pct")
        let limit = s.number("power.charge_limit_pct")
        let limitText = limit.map { $0 < 100 ? fixed($0, places: 0) : "none" } ?? "-"
        let limitUnit = limit.map { $0 < 100 ? "%" : "" } ?? ""
        return Button {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
        } label: {
            HStack(spacing: MetricColumns.gap) {
                MetricLabel(text: "Battery")
                CapacityIndicator(label: "Battery", value: percent, battery: true)
                    .frame(width: MetricColumns.bar, height: 12)
                    .overlay(alignment: .trailing) {
                        if let limit, limit > 0, limit < 100 {
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 2]))
                                .frame(width: MetricColumns.bar * (1 - limit / 100), height: 12)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .allowsHitTesting(false)
                MetricValue(value: fixed(percent, places: 0), unit: "%")
                HStack(spacing: 4) {
                    Text("Limit").frame(width: 30, alignment: .leading)
                    Text(limitText).frame(width: 32, alignment: .trailing)
                    Text(limitUnit).frame(width: 10, alignment: .leading)
                }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 0)
            }
            .frame(minHeight: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Battery settings. Dots mark the configured charge reserve, not lost capacity.")
        .accessibilityLabel("Battery \(fixed(percent, places: 0)) percent - limit \(limitText)\(limitUnit)")
        .accessibilityHint("Opens Battery settings")
    }

    private func power(_ s: Snapshot) -> some View {
        MetricSection("Power") {
            battery(s)
            MetricRow(label: "Adapter", value: fixed(s.number("power.adapter_watts")), unit: "W")
            MetricRow(label: "System", value: fixed(s.number("power.system_watts")), unit: "W")
            MetricRow(label: "Net", value: s.number("power.net_watts").map { String(format: "%+.1f", $0) } ?? "-", unit: "W")
        }
    }
}
