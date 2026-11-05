import Foundation

enum Tone { case plain, muted, success, warning, urgent, heading }
struct Piece {
    let text: String
    var tone: Tone = .plain
}
typealias Row = [Piece]
struct Section {
    let title: String
    let rows: [Row]
}

func level(_ percent: Double?) -> Tone {
    guard let percent else { return .plain }
    return percent <= 50 ? .success : percent <= 80 ? .warning : .urgent
}

private let textLabelWidth = 20
private let textBarWidth = 14
private let textValueWidth = 9

private func metricRow(_ label: String, _ value: String, unit: String = "",
                       percent: Double? = nil, bar: Bool = false, neutral: Bool = false,
                       detail: String = "") -> Row {
    var result = [Piece(text: "  " + rightPad(label, textLabelWidth))]
    if bar {
        let filled = percent.map { Int((min(100, max(0, $0)) / 10).rounded()) } ?? 0
        result.append(Piece(text: String(repeating: "█", count: filled)
                            + String(repeating: percent == nil ? "-" : "░", count: 10 - filled),
                            tone: neutral ? .plain : level(percent)))
        result.append(Piece(text: String(repeating: " ", count: textBarWidth - 10)))
    } else {
        result.append(Piece(text: String(repeating: " ", count: textBarWidth)))
    }
    result.append(Piece(text: leftPad(value, textValueWidth) + " " + rightPad(unit, 6) + detail))
    return result
}

private func tableRow(_ label: String, _ values: [String], header: Bool = false) -> Row {
    [Piece(text: "  " + rightPad(label, textLabelWidth) + String(repeating: " ", count: textBarWidth)
           + values.map { leftPad($0, textValueWidth) }.joined(separator: "  "),
           tone: header ? .muted : .plain)]
}

private func coreSection(_ group: CoreGroup) -> Section {
    let cellWidth = 20
    var rows: [Row] = []
    if !group.summaries.isEmpty {
        rows.append([Piece(text: "  " + group.summaries.map {
            rightPad($0.label, 11) + leftPad($0.value, 6) + rightPad($0.unit, 3)
        }.joined(separator: "    "), tone: .muted)])
    }
    if !group.columns.isEmpty {
        rows.append([Piece(text: "  " + group.columns.map { rightPad($0.title, cellWidth) }
            .joined(separator: "    "), tone: .muted)])
    }
    for index in 0..<group.rowCount {
        var pieces: Row = [Piece(text: "  ")]
        for (columnIndex, column) in group.columns.enumerated() {
            if columnIndex > 0 { pieces.append(Piece(text: "    ")) }
            guard index < column.cores.count else {
                pieces.append(Piece(text: String(repeating: " ", count: cellWidth)))
                continue
            }
            let core = column.cores[index]
            let filled = core.percent.map { Int((min(100, max(0, $0)) / 10).rounded()) } ?? 0
            pieces += [Piece(text: leftPad(String(core.id), 2) + " ["),
                       Piece(text: String(repeating: "█", count: filled), tone: level(core.percent)),
                       Piece(text: String(repeating: core.percent == nil ? "-" : "░", count: 10 - filled), tone: .muted),
                       Piece(text: "] " + fixed(core.percent, places: 0, width: 3, suffix: "%"))]
        }
        rows.append(pieces)
    }
    if let status = group.status { rows.append([Piece(text: "  " + status, tone: .warning)]) }
    return Section(title: group.title, rows: rows)
}

func sections(_ snapshot: Snapshot) -> [Section] {
    func n(_ key: String) -> Double? { snapshot.number(key) }
    func gib(_ key: String) -> String { fixed(n(key)) }
    func share(_ key: String, of total: String) -> String {
        fixed(snapshot.percent(key, of: total), places: 0, width: 3, suffix: "%")
    }
    let total = fixed(n("memory.total_gb"), places: 0) + " GiB"
    let bandwidth = snapshot.bandwidth
    var gpuRows = [
        metricRow("Utilization", fixed(n("gpu.utilization"), places: 0), unit: "%", percent: n("gpu.utilization"), bar: true),
        metricRow("Renderer", fixed(n("gpu.renderer_util"), places: 0), unit: "%"),
        metricRow("Tiler", fixed(n("gpu.tiler_util"), places: 0), unit: "%"),
        metricRow("Shared memory", fixed(n("memory.total_gb"), places: 0), unit: "GiB"),
        metricRow("Allocated", gib("gpu.alloc_sys_mem_gb"), unit: "GiB",
                  percent: snapshot.percent("gpu.alloc_sys_mem_gb", of: "memory.total_gb"), bar: true,
                  detail: share("gpu.alloc_sys_mem_gb", of: "memory.total_gb")),
        metricRow("In use", gib("gpu.in_use_sys_mem_gb"), unit: "GiB",
                  percent: snapshot.percent("gpu.in_use_sys_mem_gb", of: "memory.total_gb"), bar: true,
                  detail: share("gpu.in_use_sys_mem_gb", of: "memory.total_gb")),
        metricRow("Read bandwidth", fixed(bandwidth.read), unit: "GB/s",
                  percent: bandwidth.read.map { $0 * 100 / bandwidth.scale }, bar: true, neutral: true),
        metricRow("Write bandwidth", fixed(bandwidth.write), unit: "GB/s",
                  percent: bandwidth.write.map { $0 * 100 / bandwidth.scale }, bar: true, neutral: true),
        [Piece(text: "  Bandwidth scale | 0-\(fixed(bandwidth.scale, places: 0)) GB/s", tone: .muted)]
    ]
    if bandwidth.status != "Live" {
        gpuRows.append([Piece(text: "  Bandwidth " + bandwidth.status.lowercased(), tone: .warning)])
    }
    let gpu = Section(title: "GPU | \(clean(snapshot.text("gpu.model"))) | \(fixed(n("gpu.core_count"), places: 0)) cores", rows: gpuRows)
    let cpu = Section(title: "CPU | \(fixed(n("cpu.count"), places: 0)) cores", rows: [
        metricRow("Utilization", fixed(n("cpu.utilization"), places: 0), unit: "%", percent: n("cpu.utilization"), bar: true),
        metricRow("Load 1m", fixed(n("cpu.load_avg"), places: 2))
    ])
    var memoryRows = [metricRow("In use", gib("memory.in_use_gb"), unit: "GiB",
                                percent: snapshot.percent("memory.in_use_gb", of: "memory.total_gb"), bar: true,
                                detail: share("memory.in_use_gb", of: "memory.total_gb"))]
    for (label, key) in [("Free", "free_gb"), ("Active", "active_gb"), ("Wired", "wired_gb"),
                         ("  Kernel (est.)", "wired_context.kernel_baseline_gb"),
                         ("  Other wired (est.)", "wired_context.other_wired_estimate_gb"),
                         ("Inactive", "inactive_gb"), ("Speculative", "speculative_gb"),
                         ("Purgeable", "purgeable_gb"), ("Compressor", "compressor_gb"),
                         ("Reclaimable (est.)", "reclaimable_gb")] {
        memoryRows.append(metricRow(label, gib("memory." + key), unit: "GiB"))
    }
    let memory = Section(title: "MEMORY | " + total, rows: memoryRows)
    let swap = Section(title: "SWAP | " + fixed(n("swap.total_mb"), places: 0) + " MiB", rows: [
        metricRow("Used", fixed(n("swap.used_mb"), places: 0), unit: "MiB",
                  percent: snapshot.percent("swap.used_mb", of: "swap.total_mb"), bar: true,
                  detail: share("swap.used_mb", of: "swap.total_mb"))
    ])
    let pressure = snapshot.text("memory_pressure")
    let pressureTone: Tone = pressure == "OK" ? .success : pressure == "MODERATE" ? .warning : pressure == "CRITICAL" ? .urgent : .plain
    let pressureSection = Section(title: "PRESSURE", rows: [[Piece(text: "  " + pressure, tone: pressureTone)]])
    var thermalRows = [tableRow("Sensor", ["Current", "Peak", "Sensors"], header: true)]
    for (label, key) in [("CPU", "cpu"), ("GPU", "gpu"), ("Memory", "mem"), ("SoC", "soc")] {
        let current = key == "soc" ? n("thermals.soc") : n("thermals.\(key)_max")
        let count = key == "soc" ? (current == nil ? nil : 1) : n("thermals.\(key)_count")
        thermalRows.append(tableRow(label, [fixed(current), fixed(n("thermals.\(key)_peak")), fixed(count, places: 0)]))
    }
    let thermal = Section(title: "THERMALS | °C | peaks since launch", rows: thermalRows)
    let fanCount = Int(n("fans.count") ?? 0)
    var fanRows = [tableRow("Fan", ["RPM", "Min", "Max"], header: true)]
    for index in 0..<fanCount {
        let key = "fans.F\(index)"
        fanRows.append(tableRow("F\(index)", [fixed(n(key + ".rpm"), places: 0),
                                             fixed(n(key + ".min"), places: 0), fixed(n(key + ".max"), places: 0)]))
    }
    let fans = Section(title: "FANS | \(fanCount)", rows: fanRows)
    let processes = snapshot.value("cpu.top") as? [[String: Any]] ?? []
    var processRows: [Row] = [[Piece(text: "  " + leftPad("PID", 8) + "  " + leftPad("CPU %", 9) + "  Process", tone: .muted)]]
    for process in processes {
        let pid = (process["pid"] as? NSNumber)?.stringValue ?? "-"
        let usage = (process["cpu"] as? NSNumber)?.doubleValue
        processRows.append([Piece(text: "  " + leftPad(pid, 8) + "  " + fixed(usage, width: 9)
                                  + "  " + clean(process["name"] as? String ?? "-"))])
    }
    let top = Section(title: "TOP CPU", rows: processRows)
    let limit = n("power.charge_limit_pct").map { $0 < 100 ? fixed($0, places: 0, suffix: "%") : "none" } ?? "-"
    let power = Section(title: "POWER", rows: [
        metricRow("Battery", fixed(n("power.battery_pct"), places: 0), unit: "%", detail: "Limit " + limit),
        metricRow("Adapter", fixed(n("power.adapter_watts")), unit: "W"),
        metricRow("System", fixed(n("power.system_watts")), unit: "W"),
        metricRow("Net", n("power.net_watts").map { String(format: "%+.1f", $0) } ?? "-", unit: "W")
    ])
    return [cpu, coreSection(.cpu(snapshot)), top, gpu, coreSection(.gpu(snapshot.shaderCores)),
            memory, swap, pressureSection, thermal, fans, power]
}

func dashboard(_ snapshot: Snapshot) -> [Row] {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    let header = "M5 MAX | \(snapshot.text("cpu.model")) | Uptime \(snapshot.uptime) | \(formatter.string(from: snapshot.sampledAt))"
    var rows: [Row] = [[Piece(text: header, tone: .heading)], []]
    for section in sections(snapshot) {
        rows.append([Piece(text: section.title, tone: .heading)])
        rows += section.rows
        rows.append([])
    }
    return rows
}
