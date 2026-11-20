import AppKit
import ApplicationServices
import CoreGraphics

// Transcription menu bar controller.
//
// F5 (external keyboards, or Fn+F5 on the built-in keyboard) and the built-in
// keyboard's Dictation key toggle a recording. The recording runs the existing
// pipeline, `record-mic | transcribe --tmp`; when the transcript arrives it is
// placed on the clipboard and pasted at the focused insertion point.
//
// The Dictation key does not arrive as a normal key event, so every candidate
// hardware event is written to the log until its key type is identified and
// added to `dictationKeyTypes` below.

private let f5KeyCode: Int64 = 96
private let dictationKeyTypes: Set<Int> = []

private func logLine(_ message: String) {
    FileHandle.standardError.write(Data("transcription-menu: \(message)\n".utf8))
}

private enum State {
    case idle
    case recording
    case transcribing
    case done
    case failed
}

// Decorative activity waveform, not an audio-level meter. Clicks reach the menu.
private final class RecordingIcon: NSView {
    var phase = 0.0
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(x: 3, y: bounds.midY - 2.5, width: 5, height: 5)).fill()
        NSColor.labelColor.setFill()
        for index in 0..<5 {
            let height = 4 + 10 * (0.5 + 0.5 * sin(phase + Double(index) * 1.2))
            NSBezierPath(roundedRect: NSRect(x: 11 + Double(index) * 3,
                                           y: bounds.midY - height / 2, width: 2, height: height),
                         xRadius: 1, yRadius: 1).fill()
        }
    }
}

private final class MenuSpinner: NSProgressIndicator {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var toggleMenuItem: NSMenuItem!
    private var grantMenuItem: NSMenuItem!
    private var cancelMenuItem: NSMenuItem!
    private var eventTap: CFMachPort?
    private var state: State = .idle
    private var recorder: Process?
    private var recorderInput: FileHandle?
    private var transcriber: Process?
    private var profile: DictationProfile?
    private let recordingIcon = RecordingIcon()
    private let spinner = MenuSpinner()
    private var animationTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        statusItem.autosaveName = "Transcription"
        statusItem.isVisible = true
        if let button = statusItem.button {
            recordingIcon.frame = button.bounds
            recordingIcon.autoresizingMask = [.width, .height]
            button.addSubview(recordingIcon)
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.isDisplayedWhenStopped = false
            spinner.frame = NSRect(x: button.bounds.midX - 8, y: button.bounds.midY - 8, width: 16, height: 16)
            spinner.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            button.addSubview(spinner)
        }

        statusMenuItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        toggleMenuItem = NSMenuItem(title: "Start Transcription", action: #selector(toggleFromMenu), keyEquivalent: "")
        toggleMenuItem.target = self
        grantMenuItem = NSMenuItem(title: "Grant Accessibility Permission…", action: #selector(grantPermission), keyEquivalent: "")
        grantMenuItem.target = self
        cancelMenuItem = NSMenuItem(title: "Cancel Recording", action: #selector(cancelRecording), keyEquivalent: "")
        cancelMenuItem.target = self
        let quitItem = NSMenuItem(title: "Quit Transcription", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        let menu = NSMenu()
        menu.addItem(statusMenuItem)
        menu.addItem(toggleMenuItem)
        menu.addItem(cancelMenuItem)
        menu.addItem(.separator())
        menu.addItem(grantMenuItem)
        menu.addItem(quitItem)
        statusItem.menu = menu

        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        installEventTap()
        // Refresh the permission icon after grants or revocations, too.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.eventTap == nil { self.installEventTap() }
            self.updateIcon()
        }
        updateIcon()
    }

    // MARK: - Event tap

    private func installEventTap() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }
        let systemDefined = CGEventType(rawValue: 14)! // NX_SYSDEFINED, carries media/Dictation keys.
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << systemDefined.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let app = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                return app.handleEvent(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            logLine("event tap creation failed")
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logLine("event tap installed")
        updateIcon()
    }

    /// Returns nil to swallow a trigger event, or the event to let it pass.
    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == f5KeyCode {
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    let pressed = event.timestamp
                    DispatchQueue.main.async { [weak self] in self?.toggle(at: pressed, source: "f5") }
                }
                return nil
            }
            if keyCode >= 96 {
                logLine("keyDown keyCode=\(keyCode) flags=\(event.flags.rawValue)")
            }
            return Unmanaged.passUnretained(event)
        }
        if type.rawValue == 14, let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 {
            // Media and Dictation keys: data1 holds the key type and up/down state.
            let keyType = (nsEvent.data1 & 0xFFFF0000) >> 16
            let keyState = (nsEvent.data1 & 0xFF00) >> 8
            logLine("systemDefined keyType=\(keyType) keyState=\(keyState)")
            if dictationKeyTypes.contains(keyType) {
                if keyState == 0x0A { // Key down; 0x0B is key up.
                    let pressed = event.timestamp
                    DispatchQueue.main.async { [weak self] in self?.toggle(at: pressed, source: "dictation_key") }
                }
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Recording pipeline

    @objc private func toggleFromMenu() { toggle(at: uptimeNS(), source: "menu") }

    private func toggle(at pressed: UInt64, source: String) {
        switch state {
        case .idle, .done, .failed:
            profile = DictationProfile(start: pressed)
            startRecording()
        case .recording:
            profile?.stopSource = source
            profile?.marks["stop"] = pressed
            stopRecording()
        case .transcribing:
            break
        }
    }

    private func startRecording() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let link = Pipe()
        let output = Pipe()
        let control = Pipe()

        let recorder = Process()
        recorder.executableURL = URL(fileURLWithPath: home + "/.nix-profile/bin/record-mic")
        // This app owns the write end; its exit closes stdin and cancels capture.
        recorder.standardInput = control
        recorder.standardOutput = link
        recorder.standardError = FileHandle.standardError

        let transcriber = Process()
        transcriber.executableURL = URL(fileURLWithPath: home + "/.local/bin/transcribe")
        transcriber.arguments = ["--tmp"]
        transcriber.standardInput = link
        transcriber.standardOutput = output
        transcriber.standardError = FileHandle.standardError
        transcriber.environment = [
            "HOME": home,
            "PATH": "\(home)/.nix-profile/bin:\(home)/.local/bin:/usr/local/bin:/usr/bin:/bin",
        ]

        transcriber.environment?.merge(profile?.childEnvironment ?? [:]) { _, new in new }

        do {
            try recorder.run()
            try? control.fileHandleForReading.close()
            try transcriber.run()
        } catch {
            try? control.fileHandleForWriting.close()
            try? control.fileHandleForReading.close()
            try? link.fileHandleForWriting.close()
            try? link.fileHandleForReading.close()
            endProfile("launch_failed")
            logLine("could not start pipeline: \(error)")
            state = .failed
            updateIcon()
            scheduleIdleReset()
            return
        }
        // Don't keep a writer open in the parent for either reader waiting on EOF.
        try? output.fileHandleForWriting.close()
        try? link.fileHandleForWriting.close()
        try? link.fileHandleForReading.close()

        self.recorderInput = control.fileHandleForWriting
        self.recorder = recorder
        self.transcriber = transcriber
        profile?.marks["pipeline_started"] = uptimeNS()
        // One reader per recording; process termination alone isn't stdout EOF.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let eof = uptimeNS()
            transcriber.waitUntilExit()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.transcriber === transcriber else { return }
                self.profile?.marks["stdout_eof"] = eof
                self.finishTranscription(data)
            }
        }
        state = .recording
        updateIcon()
        logLine("recording started")
    }

    private func stopRecording() {
        guard let recorder, recorder.isRunning else { return }
        state = .transcribing
        updateIcon()
        // SIGINT is the stop the record-mic client forwards to its helper; the
        // helper finalizes the audio and publishes its path, which starts the
        // transcriber. SIGTERM would discard the recording.
        profile?.marks["sigint"] = uptimeNS()
        kill(recorder.processIdentifier, SIGINT)
        logLine("recording stop requested")
    }

    private func endProfile(_ outcome: String) {
        profile?.detach()
        profile?.finish(outcome)
        profile = nil
    }

    @objc private func cancelRecording() {
        endProfile("cancelled")
        try? recorderInput?.close()
        recorderInput = nil
        transcriber?.terminate()
        recorder = nil
        transcriber = nil
        state = .idle
        updateIcon()
    }

    private func finishTranscription(_ transcript: Data) {
        let run = profile
        run?.detach()
        profile = nil
        try? recorderInput?.close()
        recorderInput = nil
        recorder = nil
        transcriber = nil
        let text = String(data: transcript, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            run?.finish("no_text")
            logLine("transcription produced no text")
            state = .failed
            updateIcon()
            scheduleIdleReset()
            return
        }
        run?.marks["clipboard_begin"] = uptimeNS()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setString(text, forType: .string)
        run?.marks["clipboard_end"] = uptimeNS()
        // Leave the transcript on the clipboard; paste a copy at the insertion point.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let source = CGEventSource(stateID: .hidSystemState)
            let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
            down?.flags = .maskCommand
            let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            if down != nil { run?.marks["paste_dispatch"] = uptimeNS() }
            up?.post(tap: .cghidEventTap)
            let posted = down != nil && up != nil
            run?.finish(!copied ? "clipboard_failed" : posted ? "dispatched" : "event_failed")
            if copied && posted { logLine("transcript pasted (\(text.count) characters)") }
        }
        state = .done
        updateIcon()
        scheduleIdleReset()
    }

    // MARK: - Menu bar presentation

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let trusted = AXIsProcessTrusted()
        let recording = trusted && state == .recording
        let processing = trusted && state == .transcribing
        button.image = recording || processing ? nil : NSImage(
            systemSymbolName: trusted ? "mic" : "mic.slash", accessibilityDescription: "Transcription"
        )
        recordingIcon.isHidden = !recording
        if processing { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        if recording && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if animationTimer == nil {
                let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.recordingIcon.phase += 0.3
                    self.recordingIcon.needsDisplay = true
                }
                RunLoop.main.add(timer, forMode: .common)
                animationTimer = timer
            }
        } else {
            animationTimer?.invalidate()
            animationTimer = nil
        }
        statusMenuItem.title = switch state {
        case .idle: trusted ? "Ready" : "Accessibility Permission Required"
        case .recording: "Recording…"
        case .transcribing: "Transcribing…"
        case .done: "Pasted"
        case .failed: "Transcription Failed"
        }
        toggleMenuItem.title = state == .recording ? "Stop and Paste Transcription" : "Start Transcription"
        toggleMenuItem.isEnabled = state != .transcribing
        cancelMenuItem.isHidden = state != .recording && state != .transcribing
        grantMenuItem.isHidden = trusted
        button.toolTip = statusMenuItem.title
        button.setAccessibilityLabel(statusMenuItem.title)
    }

    private func scheduleIdleReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.state == .done || self.state == .failed else { return }
            self.state = .idle
            self.updateIcon()
        }
    }

    @objc private func grantPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        cancelRecording()
        NSApp.terminate(nil)
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
