import Foundation
import Darwin

// CGEvent.timestamp, DispatchTime.uptimeNanoseconds, CLOCK_UPTIME_RAW and
// CPython's macOS monotonic_ns all use Mach uptime, not time of day.
func uptimeNS() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

final class DictationProfile {
    private static let writer = DispatchQueue(label: "local.transcription-menu.profile", qos: .utility)
    let id = UUID().uuidString.lowercased()
    let mode: String
    var marks: [String: UInt64] = [:] // main-thread owned
    var stopSource = "none"
    private var slot: FileHandle?
    private var slotPath: String?
    private var setupNS: UInt64 = 0

    init?(start: UInt64) {
        // Re-read at each recording so a wall/detail comparison needs no app restart.
        let mode = UserDefaults.standard.string(forKey: "F5ProfileMode")
            ?? ProcessInfo.processInfo.environment["F5_PROFILE"] ?? "detail"
        guard ["detail", "summary", "wall", "sync"].contains(mode) else { return nil }
        self.mode = mode
        marks["start"] = start
        guard mode != "wall" else { return }
        let begin = uptimeNS()
        defer { setupNS = uptimeNS() - begin }
        // One bounded mailbox even after a crash. Each run retains its own open
        // inode. A late child checks the UUID before writing to the current slot.
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("local.transcription-menu.profile")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let path = dir.appendingPathComponent("pending").path
            unlink(path)
            let fd = open(path, O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC, 0o600)
            guard fd >= 0 else { return }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            slotPath = path
            try handle.write(contentsOf: Data((id + "\n").utf8))
            slot = handle
        } catch { /* A missing packet leaves UI timings available. */ }
    }

    var childEnvironment: [String: String] {
        guard let path = slotPath, slot != nil else { return [:] }
        let clock = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("transcription-clock").path
        return ["F5_PROFILE_MODE": mode, "F5_PROFILE_PACKET": path,
                "F5_PROFILE_ID": id, "F5_PROFILE_CLOCK": clock]
    }

    // Detach when the child exits/cancels, BEFORE the UI accepts the next start.
    func detach() {
        if let path = slotPath { unlink(path); slotPath = nil }
    }

    func finish(_ outcome: String) {
        let ui: [String: Any] = ["id": id, "mode": mode, "stop_source": stopSource,
                                 "menu_build": "@F5_BUILD@", "outcome": outcome,
                                 "setup_ns": setupNS, "marks": marks]
        let input = slot
        Self.writer.async {
            let project = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("projects/mlx-transcribe")
            let p = Process()
            p.executableURL = project.appendingPathComponent(".venv/bin/python")
            do {
                let bytes = try JSONSerialization.data(withJSONObject: ui)
                p.arguments = [project.appendingPathComponent("f5_profile.py").path, "collect", String(decoding: bytes, as: UTF8.self)]
                try input?.seek(toOffset: 0)
                p.standardInput = input ?? FileHandle.nullDevice
                // The collector has no access to the transcript stream.
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                try p.run()
                p.waitUntilExit()
                if p.terminationStatus == 0 { return }
            } catch {}
            FileHandle.standardError.write(Data("transcription-menu: timing summary not written\n".utf8))
        }
    }
}
