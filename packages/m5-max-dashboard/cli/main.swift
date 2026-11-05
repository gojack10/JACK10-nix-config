import Foundation
import Darwin

let arguments = Set(CommandLine.arguments.dropFirst())
let allowed: Set<String> = ["--once", "--watch", "--json", "--help", "-h"]
if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    m5-max-dashboard [--once | --watch] [--json]

    System pulse - CPU, GPU, per-core meters, memory, thermals, fans and top CPU.
    GPU shader and memory-bandwidth meters use the bridge at 127.0.0.1:8766.
    Interactive terminals watch by default. Pipes get one snapshot.
      --once   Print one reading and exit
      --watch  Refresh every second
      --json   Emit JSON instead of the aligned dashboard

    Watch keys: j/k or arrows scroll - h/l scroll sideways - g/G start/end - q quit
    """)
    exit(0)
}
if !arguments.isSubset(of: allowed) || (arguments.contains("--once") && arguments.contains("--watch")) {
    FileHandle.standardError.write(Data("m5-max-dashboard: use --help for usage\n".utf8))
    exit(2)
}
let json = arguments.contains("--json")
let terminal = isatty(STDOUT_FILENO) != 0 && ProcessInfo.processInfo.environment["TERM"] != "dumb"
let watch = arguments.contains("--watch") || (terminal && !arguments.contains("--once") && !json)
let screen = terminal && watch && !json
let keyboard = screen && isatty(STDIN_FILENO) != 0
var savedTermios = termios()
let savedFlags = fcntl(STDIN_FILENO, F_GETFL)
let hasTermios = keyboard && tcgetattr(STDIN_FILENO, &savedTermios) == 0
if hasTermios {
    var settings = savedTermios
    settings.c_lflag &= ~tcflag_t(ICANON | ECHO)
    tcsetattr(STDIN_FILENO, TCSANOW, &settings)
    _ = fcntl(STDIN_FILENO, F_SETFL, savedFlags | O_NONBLOCK)
}

func write(_ string: String) { FileHandle.standardOutput.write(Data(string.utf8)) }
func restore() {
    if hasTermios {
        tcsetattr(STDIN_FILENO, TCSANOW, &savedTermios)
        _ = fcntl(STDIN_FILENO, F_SETFL, savedFlags)
    }
    if screen { write("\u{1b}[0m\u{1b}[?25h\u{1b}[?1049l") }
}
func render(_ piece: Piece) -> String {
    guard terminal else { return piece.text }
    let style: String
    switch piece.tone {
    case .plain: return piece.text
    case .muted: style = "2"
    case .success: style = "32"
    case .warning: style = "33"
    case .urgent: style = "31"
    case .heading: style = "1;37"
    }
    return "\u{1b}[\(style)m\(piece.text)\u{1b}[0m"
}

func clipped(_ row: Row, start: Int, width: Int) -> Row {
    var position = 0
    return row.compactMap { piece in
        defer { position += piece.text.count }
        let lower = max(0, start - position)
        let upper = min(piece.text.count, start + width - position)
        guard upper > lower else { return nil }
        return Piece(text: String(piece.text.dropFirst(lower).prefix(upper - lower)), tone: piece.tone)
    }
}

var signals: [DispatchSourceSignal] = []
for value in [SIGINT, SIGTERM] {
    signal(value, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: value, queue: .global())
    source.setEventHandler { restore(); exit(0) }
    source.resume()
    signals.append(source)
}
if screen { write("\u{1b}[?1049h\u{1b}[?25l") }
defer { restore() }

let gpu = GPUReader()
do {
    gpu.refresh()
    // Prime the CPU tick delta. No lifetime-average percentage masquerading as now.
    _ = try Snapshot(full: false)
    Thread.sleep(forTimeInterval: 1)
    var nextSample = Date.distantPast
    var rows: [Row] = []
    var vertical = 0, horizontal = 0
    while true {
        var dirty = false
        if Date() >= nextSample {
            gpu.refresh()
            let readings = gpu.sample()
            let snapshot = try Snapshot(full: true, shaderCores: readings.cores, bandwidth: readings.bandwidth)
            if json {
                FileHandle.standardOutput.write(snapshot.data)
                write("\n")
            } else {
                rows = dashboard(snapshot)
                if !screen { write(rows.map { $0.map(render).joined() }.joined(separator: "\n") + "\n") }
            }
            nextSample = Date().addingTimeInterval(1)
            dirty = true
        }
        if !watch { break }
        var window = winsize()
        _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &window)
        let height = max(1, Int(window.ws_row == 0 ? 24 : window.ws_row) - 1)
        let width = max(1, Int(window.ws_col == 0 ? 80 : window.ws_col) - 1)
        if hasTermios {
            var bytes = [UInt8](repeating: 0, count: 64)
            let count = read(STDIN_FILENO, &bytes, 64)
            if count > 0 {
                var keys = String(decoding: bytes.prefix(count), as: UTF8.self)
                for (sequence, key) in [("\u{1b}[A", "k"), ("\u{1b}[B", "j"), ("\u{1b}[C", "l"),
                                        ("\u{1b}[D", "h"), ("\u{1b}[5~", "u"), ("\u{1b}[6~", "d")] {
                    keys = keys.replacingOccurrences(of: sequence, with: key)
                }
                if keys.contains("q") { break }
                for key in keys {
                    switch key {
                    case "j": vertical += 1
                    case "k": vertical -= 1
                    case "h": horizontal -= 4
                    case "l": horizontal += 4
                    case "u": vertical -= height
                    case "d": vertical += height
                    case "g": vertical = 0
                    case "G": vertical = rows.count
                    default: break
                    }
                }
                dirty = true
            }
        }
        vertical = min(max(0, rows.count - height), max(0, vertical))
        horizontal = min(max(0, (rows.map { $0.map { $0.text.count }.reduce(0, +) }.max() ?? 0) - width), max(0, horizontal))
        if screen && dirty {
            let visible = rows.dropFirst(vertical).prefix(height).map { clipped($0, start: horizontal, width: width).map(render).joined() }
            let footer = "j/k h/l | g/G | q quit | \(vertical + 1)-\(min(rows.count, vertical + height))/\(rows.count)"
            write("\u{1b}[H\u{1b}[2J" + visible.joined(separator: "\n")
                  + String(repeating: "\n", count: max(1, height - visible.count + 1)) + String(footer.prefix(width)))
        }
        Thread.sleep(forTimeInterval: screen ? 0.05 : 0.1)
    }
} catch {
    restore()
    FileHandle.standardError.write(Data("m5-max-dashboard: \(error.localizedDescription)\n".utf8))
    exit(1)
}
