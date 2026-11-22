import Foundation

// Installs the root process-memory reader as an on-demand LaunchDaemon.
// launchd owns the socket and starts the reader when the dashboard connects.
enum MemoryReader {
    private static let label = M5_MEMORY_READER_LABEL
    private static let installedPath = "/Library/PrivilegedHelperTools/\(label)"
    private static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    private static let failure = "Installing the memory reader failed."
    private static var bundledPath: String? { Bundle.main.path(forAuxiliaryExecutable: "m5-max-dashboard-memory") }

    // False when the reader is missing or older than the one in this app.
    static var isCurrent: Bool {
        guard let bundledPath else { return false }
        return FileManager.default.contentsEqual(atPath: bundledPath, andPath: installedPath)
    }

    static func install() -> String? {
        guard let bundledPath else { return "The memory reader is missing from the app." }
        let job: [String: Any] = [
            "Label": label,
            "ProgramArguments": [installedPath, String(getuid())],
            "Sockets": ["Listener": ["SockPathName": M5_MEMORY_READER_SOCKET, "SockPathMode": 0o666]]
        ]
        do {
            let plist = String(decoding: try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0),
                               as: UTF8.self)
            let result = try runAsAdministrator("""
                set -eu
                label=\(label)
                helper=\(installedPath)
                plist=\(plistPath)
                /usr/bin/install -d -o root -g wheel -m 0755 /Library/PrivilegedHelperTools
                /usr/bin/install -S -o root -g wheel -m 0755 \(shellQuoted(bundledPath)) "$helper"
                staged=$(/usr/bin/mktemp "$plist.XXXXXX")
                trap '/bin/rm -f "$staged"' EXIT
                /bin/cat > "$staged" <<'PLIST'
                \(plist)
                PLIST
                /usr/sbin/chown root:wheel "$staged"
                /bin/chmod 0644 "$staged"
                if /usr/bin/cmp -s "$staged" "$plist" && /bin/launchctl print "system/$label" >/dev/null 2>&1; then
                    # Same job: stop the running reader so the next request starts the new binary.
                    /bin/launchctl kill TERM "system/$label" 2>/dev/null || true
                else
                    /bin/launchctl bootout "system/$label" 2>/dev/null || true
                    /bin/mv -f "$staged" "$plist"
                    # Bootstrap right after bootout can fail with an I/O error while launchd finishes removal.
                    /bin/launchctl bootstrap system "$plist" || { /bin/sleep 2; /bin/launchctl bootstrap system "$plist"; }
                fi
                """)
            if result.output == "cancelled" { return nil }
            return result.error(failure)
        } catch {
            return error.localizedDescription
        }
    }
}
