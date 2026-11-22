import Foundation

struct CommandResult {
    let status: Int32
    let output: String

    func error(_ fallback: String) -> String? {
        guard status != 0 else { return nil }
        return output.isEmpty ? fallback : output
    }
}

func runCommand(_ executable: String, _ arguments: [String]) throws -> CommandResult {
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

// Runs a shell script as root after macOS asks for an administrator password.
// The output is "cancelled" when the user dismisses the password prompt.
func runAsAdministrator(_ script: String) throws -> CommandResult {
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
    return try runCommand("/usr/bin/osascript", ["-e", authorize, script])
}

func shellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
