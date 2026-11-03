import Foundation

enum Tone { case plain, success, warning, urgent, heading }
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

private func row(_ label: String, _ text: String) -> Row {
    [Piece(text: "  " + rightPad(label, 14) + text)]
}

private func barRow(_ label: String, _ percent: Double?, _ detail: String) -> Row {
    let filled = percent.map { Int((min(100, max(0, $0)) / 10).rounded()) } ?? 0
    return [Piece(text: "  " + rightPad(label, 14)),
            Piece(text: String(repeating: "█", count: filled) + String(repeating: "░", count: 10 - filled), tone: level(percent)),
            Piece(text: " " + fixed(percent, places: 0, width: 3, suffix: "%") + " | " + detail)]
}

func sections(_ snapshot: Snapshot) -> [Section] {
    func n(_ key: String) -> Double? { snapshot.number(key) }
    func gb(_ key: String) -> String { fixed(n(key), width: 6, suffix: "G") }
    let total = fixed(n("memory.total_gb"), places: 0, suffix: "G")
    let gpu = Section(title: "GPU - \(clean(snapshot.text("gpu.model"))) | \(fixed(n("gpu.core_count"), places: 0)) cores", rows: [
        barRow("util", n("gpu.utilization"),
               "render " + fixed(n("gpu.renderer_util"), places: 0, width: 3, suffix: "%")
               + " | tiler " + fixed(n("gpu.tiler_util"), places: 0, width: 3, suffix: "%")),
        barRow("alloc", snapshot.percent("gpu.alloc_sys_mem_gb", of: "memory.total_gb"),
               gb("gpu.alloc_sys_mem_gb") + " of " + total + " shared"),
        barRow("in use", snapshot.percent("gpu.in_use_sys_mem_gb", of: "memory.total_gb"),
               gb("gpu.in_use_sys_mem_gb") + " of " + total + " shared")
    ])
    let cpu = Section(title: "CPU - \(fixed(n("cpu.count"), places: 0)) cores", rows: [
        barRow("util", n("cpu.utilization"), "busy since previous sample"),
        row("load 1m", fixed(n("cpu.load_avg"), places: 2, width: 6))
    ])
    var memoryRows = [barRow("in use", snapshot.percent("memory.in_use_gb", of: "memory.total_gb"),
                             gb("memory.in_use_gb") + " | reclaimable ~" + gb("memory.reclaimable_gb").trimmingCharacters(in: .whitespaces))]
    memoryRows += [row("free", gb("memory.free_gb")),
                   row("active", gb("memory.active_gb")),
                   row("wired", gb("memory.wired_gb")),
                   row("├── kernel", gb("memory.wired_context.kernel_baseline_gb") + " | estimate"),
                   row("└── other", gb("memory.wired_context.other_wired_estimate_gb") + " | estimate"),
                   row("inactive", gb("memory.inactive_gb")),
                   row("speculative", gb("memory.speculative_gb")),
                   row("purgeable", gb("memory.purgeable_gb")),
                   row("compressor", gb("memory.compressor_gb"))]
    let memory = Section(title: "MEMORY - " + total, rows: memoryRows)
    let swap = Section(title: "SWAP - " + fixed(n("swap.total_mb"), places: 0, suffix: "M"), rows: [
        barRow("used", snapshot.percent("swap.used_mb", of: "swap.total_mb"),
               fixed(n("swap.used_mb"), places: 0, width: 6, suffix: "M"))
    ])
    let pressure = snapshot.text("memory_pressure")
    let pressureTone: Tone = pressure == "OK" ? .success : pressure == "MODERATE" ? .warning : pressure == "CRITICAL" ? .urgent : .plain
    let pressureSection = Section(title: "PRESSURE", rows: [
        [Piece(text: "  " + pressure, tone: pressureTone)]
    ])
    let thermalRows = [("cpu", "cpu"), ("gpu", "gpu"), ("memory", "mem"), ("soc", "soc")].map { label, key -> Row in
        let current = key == "soc" ? n("thermals.soc") : n("thermals.\(key)_max")
        let peak = n("thermals.\(key)_peak")
        let count = key == "soc" ? (current == nil ? nil : 1) : n("thermals.\(key)_count")
        return row(label, fixed(current, width: 6, suffix: "C") + " | max "
                   + fixed(peak, width: 6, suffix: "C") + " | "
                   + fixed(count, places: 0, width: 3) + " sensors")
    }
    let thermal = Section(title: "THERMALS - current hottest | max observed", rows: thermalRows)
    let fanCount = Int(n("fans.count") ?? 0)
    var fanRows: [Row] = []
    for index in 0..<fanCount {
        let key = "fans.F\(index)"
        let branch = index == fanCount - 1 ? "└──" : "├──"
        fanRows.append(row("\(branch) F\(index)", fixed(n(key + ".rpm"), places: 0, width: 5, suffix: " RPM")
                           + " | min " + fixed(n(key + ".min"), places: 0, width: 5)
                           + " | max " + fixed(n(key + ".max"), places: 0, width: 5)))
    }
    if fanRows.isEmpty { fanRows = [row("", "-")] }
    let fans = Section(title: "FANS - \(fanCount)", rows: fanRows)
    let processes = snapshot.value("cpu.top") as? [[String: Any]] ?? []
    var processRows = [row("PID", " CPU % | PROCESS")]
    for (index, process) in processes.enumerated() {
        let branch = index == processes.count - 1 ? "└──" : "├──"
        let pid = (process["pid"] as? NSNumber)?.intValue ?? 0
        let usage = (process["cpu"] as? NSNumber)?.doubleValue
        processRows.append(row("\(branch) \(pid)", fixed(usage, width: 6, suffix: "%")
                               + " | " + clean(process["name"] as? String ?? "-")))
    }
    let top = Section(title: "TOP CPU - ps %CPU", rows: processRows)
    let power = Section(title: "POWER", rows: [
        row("battery", fixed(n("power.battery_pct"), places: 0, width: 6, suffix: "%")),
        row("charge limit", fixed(n("power.charge_limit_pct"), places: 0, width: 6, suffix: "%") + " | configured manual ceiling"),
        row("adapter", fixed(n("power.adapter_watts"), width: 6, suffix: "W")),
        row("system", fixed(n("power.system_watts"), width: 6, suffix: "W")),
        row("net", n("power.net_watts").map { String(format: "%+6.1fW", $0) } ?? "     -W")
    ])
    return [gpu, cpu, memory, swap, pressureSection, thermal, fans, top, power]
}

func dashboard(_ snapshot: Snapshot) -> [Row] {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    let header = "M5 MAX - \(snapshot.text("cpu.model")) | uptime \(snapshot.uptime) | \(formatter.string(from: snapshot.sampledAt))"
    var rows: [Row] = [[Piece(text: header, tone: .heading)], []]
    for section in sections(snapshot) {
        rows.append([Piece(text: section.title, tone: .heading)])
        rows += section.rows
        rows.append([])
    }
    rows.append([Piece(text: "Kernel split / reclaimable are estimates | max observed since this process started")])
    return rows
}
