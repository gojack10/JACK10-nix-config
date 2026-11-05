import Foundation

struct CoreReading {
    let id: Int
    let percent: Double?
}

struct CoreColumn {
    let title: String
    let cores: [CoreReading]

    var mean: Double? {
        let values = cores.compactMap(\.percent)
        guard !values.isEmpty, values.count == cores.count else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct CoreSummary {
    let label: String
    let value: String
    var unit = "%"
}

struct CoreGroup {
    let title: String
    let summaries: [CoreSummary]
    let detail: String
    let status: String?
    let columns: [CoreColumn]

    var summary: String {
        summaries.map { "\($0.label) \($0.value)\($0.unit)" }.joined(separator: " | ")
    }

    var rowCount: Int { columns.map { $0.cores.count }.max() ?? 0 }

    static func cpu(_ snapshot: Snapshot) -> CoreGroup {
        let rows = snapshot.value("cpu.cores") as? [[String: Any]] ?? []
        let kinds = Array(Set(rows.compactMap { $0["kind"] as? String })).sorted { first, second in
            let order = ["Super", "Performance", "Efficiency", "CPU"]
            return (order.firstIndex(of: first) ?? order.count, first)
                < (order.firstIndex(of: second) ?? order.count, second)
        }
        let groups = kinds.map { kind in
            CoreColumn(title: kind, cores: rows.filter { $0["kind"] as? String == kind }.compactMap { row in
                guard let id = (row["id"] as? NSNumber)?.intValue else { return nil }
                return CoreReading(id: id, percent: (row["utilization"] as? NSNumber)?.doubleValue)
            }.sorted { $0.id < $1.id })
        }
        let columns = groups.flatMap { group in
            stride(from: 0, to: group.cores.count, by: 6).map { start in
                let cores = Array(group.cores[start..<min(start + 6, group.cores.count)])
                let range = " \(cores[0].id)-\(cores[cores.count - 1].id)"
                return CoreColumn(title: group.title + range, cores: cores)
            }
        }
        return CoreGroup(title: "CPU CORES",
                         summaries: groups.map { CoreSummary(label: $0.title, value: fixed($0.mean, places: 0)) },
                         detail: "% time busy since previous sample",
                         status: columns.isEmpty ? "Unavailable" : nil, columns: columns)
    }

    static func gpu(_ sample: GPUCoreSample) -> CoreGroup {
        let columns = (0..<4).map { column in
            let start = column * 10
            // Counter-source ranges, not a claimed physical chip floorplan.
            return CoreColumn(title: "Cores \(start)-\(start + 9)", cores: (start..<(start + 10)).map {
                CoreReading(id: $0, percent: sample.cores[$0])
            })
        }
        let values = sample.cores.compactMap { $0 }
        let mean = values.count == 40 ? values.reduce(0, +) / 40 : nil
        let peak = values.count == 40 ? values.max() : nil
        let summaries = [CoreSummary(label: "Mean", value: fixed(mean)),
                         CoreSummary(label: "Peak", value: fixed(peak, places: 0)),
                         CoreSummary(label: "Readings", value: "\(values.count)/40", unit: "")]
        let window = sample.windowMilliseconds.map { " | \($0) ms snapshots" } ?? ""
        return CoreGroup(title: "GPU SHADER THROUGHPUT | % peak", summaries: summaries,
                         detail: "% peak instruction throughput\(window) | \(sample.status)",
                         status: sample.status == "Live" ? nil
                            : sample.sampledAt != nil ? "Partial" : sample.status == "Starting" ? "Starting"
                            : sample.status.hasPrefix("Stale") ? "Stale" : "Unavailable",
                         columns: columns)
    }
}

struct GPUCoreSample {
    let cores: [Double?]
    let sampledAt: Date?
    let windowMilliseconds: Int?
    let status: String

    static func unavailable(_ reason: String) -> GPUCoreSample {
        GPUCoreSample(cores: Array(repeating: nil, count: 40), sampledAt: nil,
                      windowMilliseconds: nil, status: reason)
    }

    // Both existing research views expose /api: core-only or combined bandwidth.
    static func decode(_ data: Data) throws -> GPUCoreSample {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unavailable("Invalid bridge response")
        }
        let source = root["core"] as? [String: Any] ?? root
        let status = source["status"] as? String ?? root["status"] as? String ?? "unavailable"
        guard ["live", "partial"].contains(status) else {
            return .unavailable(["starting", "idle"].contains(status) ? "Starting"
                : clean(source["error"] as? String ?? "Bridge \(status)"))
        }
        guard let raw = (source["values"] ?? source["cores"]) as? [Any], raw.count == 40,
              let timestamp = (source["timestamp"] as? NSNumber)?.doubleValue,
              timestamp.isFinite, timestamp > 0, timestamp <= Date().timeIntervalSince1970 + 2 else {
            return .unavailable("Invalid bridge readings")
        }
        var cores: [Double?] = []
        for value in raw {
            if value is NSNull { cores.append(nil); continue }
            guard let number = value as? NSNumber, number.doubleValue.isFinite,
                  (0...100).contains(number.doubleValue) else {
                return .unavailable("Invalid bridge readings")
            }
            cores.append(number.doubleValue)
        }
        let window = ((source["window_ms"] ?? root["window_ms"]) as? NSNumber)?.intValue
        return GPUCoreSample(cores: cores, sampledAt: Date(timeIntervalSince1970: timestamp),
                             windowMilliseconds: window ?? 20,
                             status: cores.contains(where: { $0 == nil }) ? "Partial reading" : "Live")
    }

    var json: [String: Any] {
        ["cores": cores.map { $0.map { $0 as Any } ?? NSNull() },
         "timestamp": sampledAt.map { $0.timeIntervalSince1970 as Any } ?? NSNull(),
         "window_ms": windowMilliseconds.map { $0 as Any } ?? NSNull(), "status": status]
    }
}

// An optional loopback source. Never launch a debugger or wait on HTTP in the
// metrics sampler; the CPU/system pulse continues if the bridge is unavailable.
final class GPUReader {
    private let lock = NSLock()
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 0.75
        configuration.timeoutIntervalForResource = 1
        return URLSession(configuration: configuration)
    }()
    private var pending = false
    private var latest = GPUReadings.unavailable("Bridge not running :8766")

    func refresh() {
        lock.lock()
        guard !pending else { lock.unlock(); return }
        pending = true
        lock.unlock()
        let url = URL(string: "http://127.0.0.1:8766/api")!
        session.dataTask(with: url) { [weak self] data, response, error in
            guard let self else { return }
            let sample: GPUReadings
            if error != nil {
                sample = .unavailable("Bridge not running :8766")
            } else if (response as? HTTPURLResponse)?.statusCode == 200, let data,
                      let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                sample = GPUReadings(cores: (try? GPUCoreSample.decode(data)) ?? .unavailable("Invalid shader reading"),
                                     bandwidth: GPUBandwidthSample.decode(root))
            } else {
                sample = .unavailable("Bridge request failed")
            }
            self.lock.lock()
            self.latest = sample
            self.pending = false
            self.lock.unlock()
        }.resume()
    }

    func sample() -> GPUReadings {
        lock.lock()
        let result = latest
        lock.unlock()
        let cores: GPUCoreSample
        if let timestamp = result.cores.sampledAt, Date().timeIntervalSince(timestamp) > 5 {
            cores = .unavailable("Stale bridge reading")
        } else {
            cores = result.cores
        }
        return GPUReadings(cores: cores, bandwidth: result.bandwidth.fresh)
    }
}
