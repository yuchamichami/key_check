import SwiftUI
import AppKit
import AVFoundation

// MARK: - macOS virtual keycode -> (Karabiner-style name, HID usage on page 7)
// Modifier keycodes are handled separately in flagsChanged.
let kVKMap: [UInt16: (name: String, usage: Int)] = [
    0:  ("a", 0x04), 1:  ("s", 0x16), 2:  ("d", 0x07), 3:  ("f", 0x09),
    4:  ("h", 0x0B), 5:  ("g", 0x0A), 6:  ("z", 0x1D), 7:  ("x", 0x1B),
    8:  ("c", 0x06), 9:  ("v", 0x19), 11: ("b", 0x05), 12: ("q", 0x14),
    13: ("w", 0x1A), 14: ("e", 0x08), 15: ("r", 0x15), 16: ("y", 0x1C),
    17: ("t", 0x17),
    18: ("1", 0x1E), 19: ("2", 0x1F), 20: ("3", 0x20), 21: ("4", 0x21),
    22: ("6", 0x23), 23: ("5", 0x22), 25: ("9", 0x26), 26: ("7", 0x24),
    28: ("8", 0x25), 29: ("0", 0x27),
    24: ("equal_sign", 0x2E),
    27: ("hyphen", 0x2D),
    30: ("close_bracket", 0x30),
    31: ("o", 0x12), 32: ("u", 0x18),
    33: ("open_bracket", 0x2F),
    34: ("i", 0x0C), 35: ("p", 0x13),
    36: ("return_or_enter", 0x28),
    37: ("l", 0x0F), 38: ("j", 0x0D),
    39: ("quote", 0x34),
    40: ("k", 0x0E),
    41: ("semicolon", 0x33),
    42: ("backslash", 0x31),
    43: ("comma", 0x36),
    44: ("slash", 0x38),
    45: ("n", 0x11), 46: ("m", 0x10),
    47: ("period", 0x37),
    48: ("tab", 0x2B),
    49: ("spacebar", 0x2C),
    50: ("grave_accent_and_tilde", 0x35),
    51: ("delete_or_backspace", 0x2A),
    53: ("escape", 0x29),
    65: ("keypad_period", 0x63),
    67: ("keypad_asterisk", 0x55),
    69: ("keypad_plus", 0x57),
    71: ("keypad_num_lock", 0x53),
    75: ("keypad_slash", 0x54),
    76: ("keypad_enter", 0x58),
    78: ("keypad_hyphen", 0x56),
    81: ("keypad_equal_sign", 0x67),
    82: ("keypad_0", 0x62),
    83: ("keypad_1", 0x59), 84: ("keypad_2", 0x5A), 85: ("keypad_3", 0x5B),
    86: ("keypad_4", 0x5C), 87: ("keypad_5", 0x5D), 88: ("keypad_6", 0x5E),
    89: ("keypad_7", 0x5F), 91: ("keypad_8", 0x60), 92: ("keypad_9", 0x61),
    93: ("japanese_pc_yen", 0x89),
    94: ("japanese_pc_underscore", 0x87),
    95: ("japanese_pc_keypad_comma", 0x85),
    96: ("f5", 0x3E), 97: ("f6", 0x3F), 98: ("f7", 0x40), 99: ("f3", 0x3C),
    100:("f8", 0x41),101:("f9", 0x42),102:("japanese_eisuu", 0x91),
    103:("f11", 0x44),
    104:("japanese_kana", 0x90),
    105:("f13", 0x68),
    106:("f16", 0x6B),107:("f14", 0x69),109:("f10", 0x43),111:("f12", 0x45),
    113:("f15", 0x6A),
    114:("help", 0x75),
    115:("home", 0x4A),
    116:("page_up", 0x4B),
    117:("delete_forward", 0x4C),
    118:("f4", 0x3D),
    119:("end", 0x4D),
    120:("f2", 0x3B),
    121:("page_down", 0x4E),
    122:("f1", 0x3A),
    123:("left_arrow", 0x50),
    124:("right_arrow", 0x4F),
    125:("down_arrow", 0x51),
    126:("up_arrow", 0x52),
]

// Modifier keycode -> (name, HID usage, NSEvent flag) for left/right awareness
let kVKModifier: [UInt16: (name: String, usage: Int, flag: NSEvent.ModifierFlags)] = [
    54: ("right_command", 0xE7, .command),
    55: ("left_command",  0xE3, .command),
    56: ("left_shift",    0xE1, .shift),
    57: ("caps_lock",     0x39, .capsLock),
    58: ("left_option",   0xE2, .option),
    59: ("left_control",  0xE0, .control),
    60: ("right_shift",   0xE5, .shift),
    61: ("right_option",  0xE6, .option),
    62: ("right_control", 0xE4, .control),
    63: ("fn",            0x00, .function),
]

// MARK: - Models

struct KeyEvent: Identifiable {
    let id = UUID()
    let direction: String
    let label: String
    let flagsText: String
    let usagePage: Int
    let usage: Int
    let extra: String?
}

@MainActor
final class EventStore: ObservableObject {
    @Published var events: [KeyEvent] = []
    let maxEvents = 500

    func add(_ e: KeyEvent) {
        events.append(e)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }
    func clear() { events.removeAll() }

    func copyToPasteboard() {
        let lines = events.map { e -> String in
            var s = "\(e.direction)\t\(e.label)"
            if !e.flagsText.isEmpty { s += "  flags \(e.flagsText)" }
            s += String(format: "  usage page: %d (0x%04x)  usage: %d (0x%04x)",
                        e.usagePage, e.usagePage, e.usage, e.usage)
            return s
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

// MARK: - Sound (0-150% volume via EQ gain)

@MainActor
final class SoundPlayer: ObservableObject {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 0)
    private var buffer: AVAudioPCMBuffer?

    static let maxVolume: Float = 1.5

    @Published var volume: Float = 0.8 { didSet { applyVolume() } }

    enum Tone: String, CaseIterable, Identifiable {
        case click, beep, pop, tick
        var id: String { rawValue }
    }
    @Published var tone: Tone = .click { didSet { regenerateBuffer() } }

    init() {
        engine.attach(player)
        engine.attach(eq)
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(player, to: eq, format: fmt)
        engine.connect(eq, to: engine.mainMixerNode, format: fmt)
        regenerateBuffer()
        do { try engine.start(); player.play() }
        catch { NSLog("AVAudioEngine start failed: \(error)") }
        applyVolume()
    }

    func play() {
        guard let buf = buffer else { return }
        player.scheduleBuffer(buf, at: nil, options: [.interrupts], completionHandler: nil)
    }

    private func applyVolume() {
        let v = max(0, min(volume, Self.maxVolume))
        if v <= 1.0 {
            player.volume = v
            eq.globalGain = 0
        } else {
            player.volume = 1.0
            eq.globalGain = 20.0 * log10(v)
        }
    }

    private func regenerateBuffer() {
        let fmt = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = fmt.sampleRate
        let durationSec: Double; let frequency: Double; let decayRate: Double
        switch tone {
        case .click: durationSec = 0.030; frequency = 1500; decayRate = 6
        case .beep:  durationSec = 0.080; frequency = 880;  decayRate = 3
        case .pop:   durationSec = 0.025; frequency = 600;  decayRate = 5
        case .tick:  durationSec = 0.012; frequency = 4000; decayRate = 8
        }
        let frames = AVAudioFrameCount(sampleRate * durationSec)
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { return }
        buf.frameLength = frames
        let twoPi = 2.0 * Double.pi
        let amp: Float = 0.9
        for ch in 0..<Int(fmt.channelCount) {
            guard let data = buf.floatChannelData?[ch] else { continue }
            for i in 0..<Int(frames) {
                let t = Double(i) / sampleRate
                let env = Float(exp(-Double(i) / Double(frames) * decayRate))
                data[i] = Float(sin(twoPi * frequency * t)) * env * amp
            }
        }
        buffer = buf
    }
}

// MARK: - Event Monitor
//
// Modes:
//   captureMode = false (default):
//     NSEvent.addLocalMonitorForEvents — needs no permission. Captures keys/
//     mouse only when KeyCheck is the focused app. Events also flow to the
//     focused control normally.
//
//   captureMode = true:
//     CGEventTap at session level — needs Accessibility permission. CONSUMES
//     all keyboard events (returns nil), so system shortcuts (Cmd+Space,
//     Cmd+Tab fallthrough aside, Claude hotkey, etc.) won't fire while ON.
//     Mouse still uses the NSEvent path so the user can click the toggle off.

@MainActor
final class KeyMonitor: ObservableObject {
    @Published var captureMode: Bool = false {
        didSet {
            if oldValue != captureMode { applyCaptureMode() }
        }
    }
    @Published var captureError: String?
    @Published var captureActive: Bool = false  // true once tap is installed and running

    var onEvent: ((KeyEvent) -> Void)?

    private var nsMonitor: Any?
    private var cgTap: CFMachPort?
    private var cgSource: CFRunLoopSource?

    func start() {
        installNSMonitor()
    }

    func stop() {
        removeNSMonitor()
        removeCGTap()
    }

    func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    private func applyCaptureMode() {
        if captureMode {
            installCGTap()
        } else {
            removeCGTap()
        }
    }

    private func installNSMonitor() {
        guard nsMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
        ]
        nsMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            self?.handleNSEvent(e)
            return e
        }
    }

    private func removeNSMonitor() {
        if let m = nsMonitor {
            NSEvent.removeMonitor(m)
            nsMonitor = nil
        }
    }

    private func installCGTap() {
        let opts: CFDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        if !trusted {
            captureError = "Accessibility permission required. After granting in System Settings, toggle this off and back on."
            captureMode = false
            return
        }

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: _cgTapCallback,
            userInfo: ctx
        ) else {
            captureError = "CGEventTap creation failed. Accessibility may not be granted yet — try toggling off/on after granting."
            captureMode = false
            return
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        cgTap = t
        cgSource = src
        captureError = nil
        captureActive = true
    }

    private func removeCGTap() {
        if let t = cgTap { CGEvent.tapEnable(tap: t, enable: false) }
        if let src = cgSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes)
        }
        cgTap = nil
        cgSource = nil
        captureActive = false
    }

    // MARK: NSEvent path

    private func handleNSEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // When capture mode is ON, the tap consumes keyboard events before
            // they reach NSEvent. This branch only runs when capture is OFF.
            emitKey(direction: "down", keyCode: event.keyCode,
                    modifierFlags: event.modifierFlags,
                    chars: event.charactersIgnoringModifiers)
        case .keyUp:
            emitKey(direction: "up", keyCode: event.keyCode,
                    modifierFlags: event.modifierFlags,
                    chars: event.charactersIgnoringModifiers)
        case .flagsChanged:
            emitFlags(keyCode: event.keyCode, modifierFlags: event.modifierFlags)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            emitMouse(direction: "down", buttonNumber: event.buttonNumber + 1,
                      modifierFlags: event.modifierFlags)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            emitMouse(direction: "up", buttonNumber: event.buttonNumber + 1,
                      modifierFlags: event.modifierFlags)
        default: break
        }
    }

    // MARK: CGEvent path (capture mode)

    fileprivate func handleCGKey(type: CGEventType, keyCode: UInt16, flags: CGEventFlags) {
        let nsFlags = nsModFlags(from: flags)
        switch type {
        case .keyDown:
            emitKey(direction: "down", keyCode: keyCode, modifierFlags: nsFlags, chars: nil)
        case .keyUp:
            emitKey(direction: "up", keyCode: keyCode, modifierFlags: nsFlags, chars: nil)
        case .flagsChanged:
            emitFlags(keyCode: keyCode, modifierFlags: nsFlags)
        default: break
        }
    }

    private func nsModFlags(from cg: CGEventFlags) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if cg.contains(.maskShift)       { f.insert(.shift) }
        if cg.contains(.maskControl)     { f.insert(.control) }
        if cg.contains(.maskAlternate)   { f.insert(.option) }
        if cg.contains(.maskCommand)     { f.insert(.command) }
        if cg.contains(.maskAlphaShift)  { f.insert(.capsLock) }
        if cg.contains(.maskSecondaryFn) { f.insert(.function) }
        return f
    }

    // MARK: Shared emitters

    private func emitKey(direction: String, keyCode: UInt16,
                         modifierFlags: NSEvent.ModifierFlags, chars: String?) {
        let entry = kVKMap[keyCode]
        let name = entry?.name ?? "key_code_\(keyCode)"
        let usage = entry?.usage ?? 0
        let extra: String
        if let chars = chars, !chars.isEmpty {
            let escaped = chars
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            extra = "chars: \"\(escaped)\"  code: \(keyCode)"
        } else {
            extra = "code: \(keyCode) (0x\(String(format: "%02x", keyCode)))"
        }
        onEvent?(KeyEvent(
            direction: direction,
            label: "{\"key_code\":\"\(name)\"}",
            flagsText: flagsString(modifierFlags),
            usagePage: 0x07,
            usage: usage,
            extra: extra
        ))
    }

    private func emitFlags(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        guard let mod = kVKModifier[keyCode] else {
            onEvent?(KeyEvent(
                direction: "down",
                label: "{\"key_code\":\"modifier_\(keyCode)\"}",
                flagsText: flagsString(modifierFlags),
                usagePage: 0x07,
                usage: 0,
                extra: "code: \(keyCode)"
            ))
            return
        }
        let direction = modifierFlags.contains(mod.flag) ? "down" : "up"
        onEvent?(KeyEvent(
            direction: direction,
            label: "{\"key_code\":\"\(mod.name)\"}",
            flagsText: flagsString(modifierFlags),
            usagePage: 0x07,
            usage: mod.usage,
            extra: nil
        ))
    }

    private func emitMouse(direction: String, buttonNumber: Int,
                           modifierFlags: NSEvent.ModifierFlags) {
        onEvent?(KeyEvent(
            direction: direction,
            label: "{\"pointing_button\":\"button\(buttonNumber)\"}",
            flagsText: flagsString(modifierFlags),
            usagePage: 0x09,
            usage: buttonNumber,
            extra: nil
        ))
    }

    private func flagsString(_ f: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if f.contains(.capsLock) { parts.append("caps_lock") }
        if f.contains(.shift)    { parts.append("shift") }
        if f.contains(.control)  { parts.append("control") }
        if f.contains(.option)   { parts.append("option") }
        if f.contains(.command)  { parts.append("command") }
        if f.contains(.function) { parts.append("fn") }
        return parts.joined(separator: ",")
    }
}

// CGEventTap callback — runs on the main run loop because we registered with
// CFRunLoopGetCurrent() (called from the main thread). Returns nil to consume
// the event so it never reaches other apps.
private func _cgTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()

    // OS may disable the tap on timeout / user-input events. Re-enable.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Caller (KeyMonitor.installCGTap) holds the CFMachPort; we just ignore.
        return Unmanaged.passUnretained(event)
    }

    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags
    Task { @MainActor in
        monitor.handleCGKey(type: type, keyCode: keyCode, flags: flags)
    }
    return nil  // consume — block from reaching other apps
}

// MARK: - Views

struct EventRow: View {
    let event: KeyEvent
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.direction)
                .font(.system(size: 24, weight: .light))
                .foregroundColor(event.direction == "down" ? .green : .orange)
                .frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.label)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.white)
                if !event.flagsText.isEmpty {
                    Text("flags \(event.flagsText)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                }
                if let extra = event.extra {
                    Text(extra)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "usage page: %d (0x%04x)", event.usagePage, event.usagePage))
                Text(String(format: "usage: %d (0x%04x)", event.usage, event.usage))
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.gray)
        }
        .padding(.vertical, 2)
    }
}

struct ContentView: View {
    @StateObject private var store = EventStore()
    @StateObject private var sound = SoundPlayer()
    @StateObject private var monitor = KeyMonitor()
    @State private var soundEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                Toggle("Sound", isOn: $soundEnabled).toggleStyle(.switch)
                Picker("", selection: $sound.tone) {
                    ForEach(SoundPlayer.Tone.allCases) { t in
                        Text(t.rawValue.capitalized).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .labelsHidden()
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill").foregroundColor(.secondary)
                    Slider(value: $sound.volume, in: 0...SoundPlayer.maxVolume)
                        .frame(width: 160)
                    Image(systemName: "speaker.wave.3.fill").foregroundColor(.secondary)
                    Text("\(Int(sound.volume * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 40, alignment: .trailing)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Test")  { sound.play() }
                Button("Copy")  { store.copyToPasteboard() }
                Button("Clear") { store.clear() }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Capture mode row
            HStack(spacing: 12) {
                Toggle("Capture mode (block system shortcuts)", isOn: $monitor.captureMode)
                    .toggleStyle(.switch)
                if monitor.captureActive {
                    Text("● BLOCKING ALL KEYBOARD INPUT — click toggle to stop")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.red)
                } else if let err = monitor.captureError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.orange)
                    Button("Open Accessibility Settings") {
                        monitor.openAccessibilitySettings()
                    }
                } else {
                    Text("(NSEvent local — no permission needed)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal)

            Divider()

            HStack {
                Text("Keyboard & pointing events")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.events) { e in
                            EventRow(event: e)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(
                                    Color.white.opacity(0.02)
                                        .overlay(Rectangle().frame(height: 0.5)
                                            .foregroundColor(.white.opacity(0.06))
                                            .frame(maxHeight: .infinity, alignment: .bottom))
                                )
                                .id(e.id)
                        }
                    }
                }
                .background(Color.black)
                .onChange(of: store.events.count) { _ in
                    if let last = store.events.last {
                        withAnimation(.linear(duration: 0.08)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .onAppear {
            monitor.onEvent = { [weak store, weak sound] e in
                store?.add(e)
                if soundEnabled { sound?.play() }
            }
            monitor.start()
        }
    }
}

@main
struct KeyCheckApp: App {
    var body: some Scene {
        WindowGroup("KeyCheck") {
            ContentView().preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
    }
}
