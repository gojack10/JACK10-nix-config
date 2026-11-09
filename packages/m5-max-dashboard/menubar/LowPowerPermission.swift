import Foundation

enum LowPowerPermission {
    private static let uid = getuid()
    private static let rulePath = "/private/etc/sudoers.d/m5-max-dashboard-low-power-\(uid)"

    static func apply(mode: Int, scope: String) -> String? {
        // Ignore cached credentials so a successful toggle always uses the standing grant.
        let arguments = ["-n", "-k", "-u", "root", "--", "/usr/bin/pmset", scope, "powermode", String(mode)]
        do {
            let result = try run("/usr/bin/sudo", arguments)
            guard result.output == "sudo: a password is required", result.status != 0 else {
                return result.error
            }

            guard !FileManager.default.fileExists(atPath: rulePath) else {
                return "macOS isn’t using the saved Low Power Mode permission."
            }
            let approval = try installPermission()
            if let error = approval.error { return error }
            if approval.output == "cancelled" { return nil }
            return try run("/usr/bin/sudo", arguments).error
        } catch {
            return error.localizedDescription
        }
    }

    private static func installPermission() throws -> CommandResult {
        let install = """
            set -eu
            rule=\(rulePath)
            staged=$(/usr/bin/mktemp "$rule.XXXXXX")
            trap '/bin/rm -f "$staged"' EXIT
            /bin/cat > "$staged" <<'RULE'
            #\(uid) ALL=(root) NOSETENV: NOPASSWD: /usr/bin/pmset -b powermode 0, /usr/bin/pmset -b powermode 1, /usr/bin/pmset -c powermode 0, /usr/bin/pmset -c powermode 1
            RULE
            /usr/sbin/chown root:wheel "$staged"
            /bin/chmod 0440 "$staged"
            /usr/sbin/visudo -q -c -f "$staged"
            # A dotted staging name is ignored by sudo. Publish the checked file without replacing an existing rule.
            if [ -e "$rule" ]; then
                /usr/bin/cmp "$staged" "$rule"
            else
                /bin/ln -h "$staged" "$rule"
            fi
            """
        let authorize = """
            on run argv
                try
                    do shell script (item 1 of argv) with administrator privileges
                on error messageText number errorNumber
                    if errorNumber is -128 then return "cancelled"
                    error messageText number errorNumber
                end try
            end run
            """
        return try run("/usr/bin/osascript", ["-e", authorize, install])
    }

    private struct CommandResult {
        let status: Int32
        let output: String

        var error: String? {
            guard status != 0 else { return nil }
            return output.isEmpty ? "The power setting command failed." : output
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C"]) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus,
                             output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
