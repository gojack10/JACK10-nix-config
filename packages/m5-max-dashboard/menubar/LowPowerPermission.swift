import Foundation

enum LowPowerPermission {
    private static let uid = getuid()
    private static let rulePath = "/private/etc/sudoers.d/m5-max-dashboard-low-power-\(uid)"
    private static let failure = "The power setting command failed."

    static func apply(mode: Int, scope: String) -> String? {
        // Ignore cached credentials so a successful toggle always uses the standing grant.
        let arguments = ["-n", "-k", "-u", "root", "--", "/usr/bin/pmset", scope, "powermode", String(mode)]
        do {
            let result = try runCommand("/usr/bin/sudo", arguments)
            guard result.output == "sudo: a password is required", result.status != 0 else {
                return result.error(failure)
            }

            guard !FileManager.default.fileExists(atPath: rulePath) else {
                return "macOS isn’t using the saved Low Power Mode permission."
            }
            let approval = try installPermission()
            if let error = approval.error(failure) { return error }
            if approval.output == "cancelled" { return nil }
            return try runCommand("/usr/bin/sudo", arguments).error(failure)
        } catch {
            return error.localizedDescription
        }
    }

    private static func installPermission() throws -> CommandResult {
        try runAsAdministrator("""
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
            """)
    }
}
