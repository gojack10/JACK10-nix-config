import Foundation

struct GPUBandwidthSample {
    static let source = "IOReport / AMC / PRIM GFX DCS"
    let read: Double?
    let write: Double?
    let sampledAt: Date?
    let seconds: Double?
    let status: String
    let detail: String

    static func unavailable(_ detail: String, status: String = "Unavailable") -> GPUBandwidthSample {
        GPUBandwidthSample(read: nil, write: nil, sampledAt: nil, seconds: nil,
                           status: status, detail: detail)
    }

    static func decode(_ root: [String: Any]) -> GPUBandwidthSample {
        guard let data = root["controller"] as? [String: Any] else {
            return .unavailable("GPU memory-controller source unavailable")
        }
        guard data["status"] as? String == "live" else {
            let starting = ["starting", "idle"].contains(data["status"] as? String ?? "")
            return .unavailable(clean(data["error"] as? String ?? "Controller starting"),
                                status: starting ? "Starting" : "Unavailable")
        }
        // Never substitute GPU-fabric or whole-system DRAM rates for these counters.
        guard data["source"] as? String == source, data["unit"] as? String == "GB/s",
              let read = (data["read_gb_s"] as? NSNumber)?.doubleValue,
              let write = (data["write_gb_s"] as? NSNumber)?.doubleValue,
              let timestamp = (data["timestamp"] as? NSNumber)?.doubleValue,
              let seconds = (data["seconds"] as? NSNumber)?.doubleValue,
              read.isFinite, write.isFinite, read >= 0, write >= 0,
              seconds.isFinite, seconds > 0, seconds <= 10,
              timestamp.isFinite, timestamp > 0, timestamp <= Date().timeIntervalSince1970 + 2 else {
            return .unavailable("Invalid GPU memory-controller reading")
        }
        return GPUBandwidthSample(read: read, write: write,
                                   sampledAt: Date(timeIntervalSince1970: timestamp), seconds: seconds,
                                   status: "Live", detail: source + " | decimal GB/s")
    }

    var fresh: GPUBandwidthSample {
        guard let sampledAt, Date().timeIntervalSince(sampledAt) > 5 else { return self }
        return .unavailable("GPU memory-controller reading is over five seconds old", status: "Stale")
    }

    // A shared chart range, not a calibrated hardware ceiling. Expand both bars
    // together when needed; never silently clip a higher measured rate.
    var scale: Double {
        max(250, ceil(max(read ?? 0, write ?? 0) / 250) * 250)
    }

    var json: [String: Any] {
        ["read_gb_s": read.map { $0 as Any } ?? NSNull(),
         "write_gb_s": write.map { $0 as Any } ?? NSNull(),
         "timestamp": sampledAt.map { $0.timeIntervalSince1970 as Any } ?? NSNull(),
         "seconds": seconds.map { $0 as Any } ?? NSNull(),
         "source": Self.source, "unit": "GB/s", "status": status]
    }
}

struct GPUReadings {
    let cores: GPUCoreSample
    let bandwidth: GPUBandwidthSample

    static func unavailable(_ reason: String) -> GPUReadings {
        GPUReadings(cores: .unavailable(reason), bandwidth: .unavailable(reason))
    }
}
