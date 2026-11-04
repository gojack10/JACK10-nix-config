import AppKit
import SwiftUI

final class DashboardModel: ObservableObject {
    @Published var snapshot: Snapshot?
    @Published var error: String?
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
        if battery {
            // More battery is good; do not reuse the utilization warning scale.
            let color: NSColor = (value ?? 100) <= 10 ? .systemRed : (value ?? 100) <= 25 ? .systemOrange : .systemGreen
            indicator.fillColor = color
            indicator.warningFillColor = color
            indicator.criticalFillColor = color
        }
        indicator.setAccessibilityLabel(value == nil ? "\(label) - unavailable" : label)
    }
}

private struct MetricRow: View {
    let label: String
    let value: String
    var detail = ""
    var percent: Double? = nil
    var bar = false
    var child = false

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(child ? .secondary : .primary)
                .padding(.leading, child ? 12 : 0)
                .frame(width: 100, alignment: .leading)
            if bar { CapacityIndicator(label: label, value: percent).frame(width: 118, height: 12) }
            else { Color.clear.frame(width: 118, height: 1) }
            Text(value).monospacedDigit().frame(width: 72, alignment: .trailing)
            Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
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
            if !group.summary.isEmpty {
                Text(group.summary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            // Equal-width lanes fill the panel; fixed ID/value fields keep every
            // bar aligned. CPU has three six-core lanes, GPU four ten-core lanes.
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
            Text(group.detail).font(.caption2).foregroundStyle(.secondary)
        }
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
                        CoreMeters(title: "GPU shader cores", group: .gpu(s.shaderCores))
                        Divider()
                        memory(s)
                        Divider()
                        swap(s)
                        Divider()
                        MetricSection("Pressure") {
                            Text(s.text("memory_pressure"))
                                .foregroundStyle(s.text("memory_pressure") == "OK" ? Color(nsColor: .green)
                                    : s.text("memory_pressure") == "CRITICAL" ? Color(nsColor: .red)
                                    : s.text("memory_pressure") == "MODERATE" ? Color(nsColor: .yellow) : .primary)
                        }
                        Divider()
                        thermals(s)
                        Divider()
                        fans(s)
                        Divider()
                        power(s)
                    }
                    .padding(16)
                } else {
                    ProgressView("Collecting system stats")
                        .frame(maxWidth: .infinity).padding(32)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Kernel split / reclaimable are estimates | thermal max observed since app start")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button(action: copyAllStats) {
                        Label("Copy All Stats", systemImage: "doc.on.doc")
                    }
                    .disabled(model.snapshot == nil)
                    .help("Copy the complete displayed snapshot, including offscreen sections, as aligned text")
                    Button("Open Web", action: openWeb)
                    Text(copyFeedback).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Button("Quit", action: quit)
                }
                .controlSize(.small)
            }
            .padding(12)
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func copyAllStats() {
        guard let snapshot = model.snapshot else { return }
        var text = dashboard(snapshot).map { $0.map(\.text).joined() }.joined(separator: "\n") + "\n"
        if let error = model.error {
            text = "STALE SNAPSHOT - \(clean(error))\n\n" + text
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        copyFeedback = pasteboard.setString(text, forType: .string)
            ? "Copied \(snapshot.sampledAt.formatted(date: .omitted, time: .standard))" : "Copy failed"
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
                Text("Uptime \(s.uptime)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if let error = model.error {
                Text("Read failed - \(clean(error)) | last reading is stale")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func gpu(_ s: Snapshot) -> some View {
        MetricSection("GPU - \(clean(s.text("gpu.model"))) | \(fixed(s.number("gpu.core_count"), places: 0)) cores") {
            MetricRow(label: "Utilization", value: fixed(s.number("gpu.utilization"), places: 0, suffix: "%"),
                      detail: "render \(fixed(s.number("gpu.renderer_util"), places: 0))% | tiler \(fixed(s.number("gpu.tiler_util"), places: 0))%",
                      percent: s.number("gpu.utilization"), bar: true)
            MetricRow(label: "Allocated", value: fixed(s.number("gpu.alloc_sys_mem_gb"), suffix: "G"),
                      detail: "\(fixed(s.percent("gpu.alloc_sys_mem_gb", of: "memory.total_gb"), places: 0))% | of \(fixed(s.number("memory.total_gb"), places: 0))G shared",
                      percent: s.percent("gpu.alloc_sys_mem_gb", of: "memory.total_gb"), bar: true)
            MetricRow(label: "In use", value: fixed(s.number("gpu.in_use_sys_mem_gb"), suffix: "G"),
                      detail: "\(fixed(s.percent("gpu.in_use_sys_mem_gb", of: "memory.total_gb"), places: 0))% | of \(fixed(s.number("memory.total_gb"), places: 0))G shared",
                      percent: s.percent("gpu.in_use_sys_mem_gb", of: "memory.total_gb"), bar: true)
        }
    }

    private func cpu(_ s: Snapshot) -> some View {
        MetricSection("CPU - \(fixed(s.number("cpu.count"), places: 0)) cores") {
            MetricRow(label: "Utilization", value: fixed(s.number("cpu.utilization"), places: 0, suffix: "%"),
                      detail: "since previous sample", percent: s.number("cpu.utilization"), bar: true)
            MetricRow(label: "Load 1m", value: fixed(s.number("cpu.load_avg"), places: 2))
        }
    }

    private func memory(_ s: Snapshot) -> some View {
        MetricSection("Memory - \(fixed(s.number("memory.total_gb"), places: 0))G") {
            MetricRow(label: "In use", value: fixed(s.number("memory.in_use_gb"), suffix: "G"),
                      detail: "\(fixed(s.percent("memory.in_use_gb", of: "memory.total_gb"), places: 0))% | reclaimable ~\(fixed(s.number("memory.reclaimable_gb")))G",
                      percent: s.percent("memory.in_use_gb", of: "memory.total_gb"), bar: true)
            MetricRow(label: "Free", value: fixed(s.number("memory.free_gb"), suffix: "G"))
            MetricRow(label: "Active", value: fixed(s.number("memory.active_gb"), suffix: "G"))
            MetricRow(label: "Wired", value: fixed(s.number("memory.wired_gb"), suffix: "G"))
            MetricRow(label: "Kernel", value: fixed(s.number("memory.wired_context.kernel_baseline_gb"), suffix: "G"), detail: "estimate", child: true)
            MetricRow(label: "Other wired", value: fixed(s.number("memory.wired_context.other_wired_estimate_gb"), suffix: "G"), detail: "estimate", child: true)
            MetricRow(label: "Inactive", value: fixed(s.number("memory.inactive_gb"), suffix: "G"))
            MetricRow(label: "Speculative", value: fixed(s.number("memory.speculative_gb"), suffix: "G"))
            MetricRow(label: "Purgeable", value: fixed(s.number("memory.purgeable_gb"), suffix: "G"))
            MetricRow(label: "Compressor", value: fixed(s.number("memory.compressor_gb"), suffix: "G"))
        }
    }

    private func swap(_ s: Snapshot) -> some View {
        MetricSection("Swap - \(fixed(s.number("swap.total_mb"), places: 0))M") {
            MetricRow(label: "Used", value: fixed(s.number("swap.used_mb"), places: 0, suffix: "M"),
                      detail: fixed(s.percent("swap.used_mb", of: "swap.total_mb"), places: 0, suffix: "%"),
                      percent: s.percent("swap.used_mb", of: "swap.total_mb"), bar: true)
        }
    }

    private func thermals(_ s: Snapshot) -> some View {
        MetricSection("Thermals - current hottest | max observed") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                GridRow {
                    Text("Sensor").frame(width: 100, alignment: .leading)
                    Text("Current").frame(width: 80, alignment: .trailing)
                    Text("Max").frame(width: 80, alignment: .trailing)
                    Text("Sensors").frame(width: 64, alignment: .trailing)
                }.font(.caption).foregroundStyle(.secondary)
                ForEach(["cpu", "gpu", "mem", "soc"], id: \.self) { key in
                    let current = s.number(key == "soc" ? "thermals.soc" : "thermals.\(key)_max")
                    let peak = s.number("thermals.\(key)_peak")
                    GridRow {
                        Text(key == "mem" ? "Memory" : key.uppercased())
                        Text(fixed(current, suffix: " °C"))
                            .foregroundStyle(temperatureColor(current))
                            .frame(width: 80, alignment: .trailing)
                        Text(fixed(peak, suffix: " °C"))
                            .foregroundStyle(temperatureColor(peak))
                            .frame(width: 80, alignment: .trailing)
                        Text(key == "soc" ? (s.number("thermals.soc") == nil ? "-" : "1")
                            : fixed(s.number("thermals.\(key)_count"), places: 0))
                            .frame(width: 64, alignment: .trailing)
                    }.monospacedDigit()
                }
            }
        }
    }

    private func fans(_ s: Snapshot) -> some View {
        MetricSection("Fans - \(Int(s.number("fans.count") ?? 0))") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                GridRow {
                    Text("Fan").frame(width: 100, alignment: .leading)
                    Text("RPM").frame(width: 80, alignment: .trailing)
                    Text("Min").frame(width: 80, alignment: .trailing)
                    Text("Max").frame(width: 80, alignment: .trailing)
                }.font(.caption).foregroundStyle(.secondary)
                ForEach(0..<Int(s.number("fans.count") ?? 0), id: \.self) { i in
                    GridRow {
                        Text("F\(i)")
                        Text(fixed(s.number("fans.F\(i).rpm"), places: 0)).frame(width: 80, alignment: .trailing)
                        Text(fixed(s.number("fans.F\(i).min"), places: 0)).frame(width: 80, alignment: .trailing)
                        Text(fixed(s.number("fans.F\(i).max"), places: 0)).frame(width: 80, alignment: .trailing)
                    }.monospacedDigit()
                }
            }
        }
    }

    private func processes(_ s: Snapshot) -> some View {
        let rows = s.value("cpu.top") as? [[String: Any]] ?? []
        return MetricSection("Top CPU - ps %CPU") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                GridRow {
                    Text("PID").frame(width: 64, alignment: .trailing)
                    Text("CPU %").frame(width: 64, alignment: .trailing)
                    Text("Process").frame(maxWidth: .infinity, alignment: .leading)
                }.font(.caption).foregroundStyle(.secondary)
                ForEach(rows.indices, id: \.self) { i in
                    GridRow {
                        Text((rows[i]["pid"] as? NSNumber)?.stringValue ?? "-").frame(width: 64, alignment: .trailing)
                        Text(fixed((rows[i]["cpu"] as? NSNumber)?.doubleValue, suffix: "%")).frame(width: 64, alignment: .trailing)
                        Text(clean(rows[i]["name"] as? String ?? "-")).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(clean(rows[i]["name"] as? String ?? "-"))
                    }.monospacedDigit()
                }
            }
        }
    }

    private func battery(_ s: Snapshot) -> some View {
        let percent = s.number("power.battery_pct")
        let limit = s.number("power.charge_limit_pct")
        let detail = limit.map { $0 < 100 ? "\(fixed($0, places: 0))% configured limit" : "No manual limit" } ?? "Charge limit unavailable"
        return Button {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
        } label: {
            HStack(spacing: 12) {
                Text("Battery").frame(width: 100, alignment: .leading)
                CapacityIndicator(label: "Battery", value: percent, battery: true)
                    .frame(width: 118, height: 12)
                    .overlay(alignment: .trailing) {
                        if let limit, limit > 0, limit < 100 {
                            // Keep actual charge visible if macOS charges beyond the preference.
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [1, 2]))
                                .frame(width: 118 * (1 - limit / 100), height: 12)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .allowsHitTesting(false)
                Text(fixed(percent, places: 0, suffix: "%")).monospacedDigit().frame(width: 72, alignment: .trailing)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open Battery settings. Dots mark the configured charge reserve, not lost capacity or a guarantee of enforcement.")
        .accessibilityLabel("Battery \(fixed(percent, places: 0)) percent - \(detail)")
        .accessibilityHint("Opens Battery settings")
    }

    private func power(_ s: Snapshot) -> some View {
        MetricSection("Power") {
            battery(s)
            MetricRow(label: "Adapter", value: fixed(s.number("power.adapter_watts"), suffix: "W"))
            MetricRow(label: "System", value: fixed(s.number("power.system_watts"), suffix: "W"))
            MetricRow(label: "Net", value: s.number("power.net_watts").map { String(format: "%+.1fW", $0) } ?? "-")
        }
    }
}
