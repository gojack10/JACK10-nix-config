import Foundation

struct Snapshot {
    let data: Data
    let values: [String: Any]
    let shaderCores: GPUCoreSample

    init(full: Bool, shaderCores: GPUCoreSample = .unavailable("Bridge not running :8766")) throws {
        let capacity = 32768
        var buffer = [CChar](repeating: 0, count: capacity)
        m5_sample(&buffer, Int32(capacity), full ? 1 : 0)
        let nativeData = Data(buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) })
        guard var object = try JSONSerialization.jsonObject(with: nativeData) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        if let message = object["error"] as? String {
            throw NSError(domain: "m5-max-dashboard", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        self.shaderCores = shaderCores
        if full {
            var gpu = object["gpu"] as? [String: Any] ?? [:]
            gpu["shader_cores"] = shaderCores.json
            object["gpu"] = gpu
        }
        values = object
        data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    func value(_ path: String) -> Any? {
        path.split(separator: ".").reduce(values as Any?) { object, key in
            (object as? [String: Any])?[String(key)]
        }
    }

    func number(_ path: String) -> Double? { (value(path) as? NSNumber)?.doubleValue }
    func text(_ path: String) -> String { value(path) as? String ?? "-" }
    func percent(_ numerator: String, of denominator: String) -> Double? {
        guard let top = number(numerator), let bottom = number(denominator), bottom > 0 else { return nil }
        return top * 100 / bottom
    }

    var sampledAt: Date { Date(timeIntervalSince1970: number("sampled_at") ?? 0) }
    var uptime: String {
        guard let seconds = number("uptime_seconds") else { return "-" }
        return "\(Int(seconds) / 3600)h \(Int(seconds) % 3600 / 60)m"
    }
}

func fixed(_ value: Double?, places: Int = 1, width: Int = 0, suffix: String = "") -> String {
    guard let value, value.isFinite else { return leftPad("-", width) + suffix }
    return String(format: "%*.*f", width, places, value) + suffix
}

func leftPad(_ value: String, _ width: Int) -> String {
    String(repeating: " ", count: max(0, width - value.count)) + value
}

func rightPad(_ value: String, _ width: Int) -> String {
    value + String(repeating: " ", count: max(0, width - value.count))
}

func clean(_ value: String) -> String {
    String(value.map { $0.isNewline || $0 == "\t" || $0 == "\u{1b}" ? " " : $0 })
        .replacingOccurrences(of: "·", with: "-")
}
