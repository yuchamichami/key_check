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

// MARK: - Event Monitor (NSEvent local — no permission required)

@MainActor
final class KeyMonitor: ObservableObject {
    var onEvent: ((KeyEvent) -> Void)?
    private var localMonitor: Any?

    func start() {
        guard localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
        ]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            self?.handle(e)
            return e
        }
    }

    func stop() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
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

    // MARK: Emitters

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

// MARK: - Design tokens (from Cladesign_export2/tokens.json)

extension Color {
    static let bgWindow      = Color(red: 0.043, green: 0.063, blue: 0.188) // #0B1030
    static let bgWindowGrad  = Color(red: 0.090, green: 0.075, blue: 0.278) // #171347
    static let bgCard        = Color(red: 0.055, green: 0.059, blue: 0.141) // #0E0F24
    static let bgCardHover   = Color(red: 0.075, green: 0.078, blue: 0.157) // #131428
    static let accentCyan    = Color(red: 0.357, green: 0.820, blue: 1.000) // #5BD1FF
    static let accentCyan2   = Color(red: 0.180, green: 0.545, blue: 1.000) // #2E8BFF
    static let downGreen     = Color(red: 0.357, green: 1.000, blue: 0.545) // #5BFF8B
    static let upOrange      = Color(red: 1.000, green: 0.659, blue: 0.357) // #FFA85B
    static let peakRed       = Color(red: 1.000, green: 0.373, blue: 0.373) // #FF5F5F
    static let textPrimary   = Color(red: 0.925, green: 0.933, blue: 1.000) // #ECEEFF
    static let textSecondary = Color(red: 0.490, green: 0.502, blue: 0.565) // #7D8090
    static let knobLight     = Color(red: 0.227, green: 0.239, blue: 0.290) // #3A3D4A
    static let knobDark      = Color(red: 0.114, green: 0.122, blue: 0.157) // #1D1F28
    static let keycapTopL    = Color(red: 0.988, green: 0.988, blue: 0.996) // #FCFCFE
    static let keycapTopD    = Color(red: 0.824, green: 0.824, blue: 0.871) // #D2D2DE
    static let keycapSideL   = Color(red: 0.651, green: 0.651, blue: 0.722) // #A6A6B8
    static let keycapSideD   = Color(red: 0.353, green: 0.353, blue: 0.439) // #5A5A70
    static let dividerLine   = Color.white.opacity(0.04)
}

// MARK: - Window background (gradient + subtle vignette)

struct WindowBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.bgWindowGrad, .bgWindow],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.accentCyan2.opacity(0.10), .clear],
                center: .topLeading,
                startRadius: 0, endRadius: 800
            )
            .blendMode(.plusLighter)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Volume knob

struct VolumeKnob: View {
    @Binding var value: Float            // 0 ... 1.5
    let maxValue: Float                  // 1.5
    @State private var dragStartValue: Float? = nil

    private let diameter: CGFloat = 84
    private let arcStart: Double = -135
    private let arcEnd: Double   =  135
    private let strokeWidth: CGFloat = 3

    private var pct: Int { Int((value * 100).rounded()) }
    private var fraction: Double { Double(value / maxValue) }   // 0...1
    private var fractionAt100: Double { Double(1.0 / maxValue) } // 1.0/1.5
    private var indicatorAngle: Angle {
        .degrees(arcStart + (arcEnd - arcStart) * fraction)
    }
    private var isPeak: Bool { value > 1.0 }

    var body: some View {
        ZStack {
            // outer drop shadow base
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: diameter + 8, height: diameter + 8)
                .blur(radius: 8)
                .offset(y: 4)

            // background (un-lit) arc
            ArcShape(start: arcStart, end: arcEnd)
                .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .frame(width: diameter, height: diameter)

            // lit arc (0% → 100% in cyan)
            ArcShape(
                start: arcStart,
                end: arcStart + (arcEnd - arcStart) * min(fraction, fractionAt100)
            )
            .stroke(
                LinearGradient(
                    colors: [.accentCyan2, .accentCyan],
                    startPoint: .leading, endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
            .frame(width: diameter, height: diameter)
            .shadow(color: .accentCyan.opacity(0.55), radius: 6)

            // peak arc (100% → current in orange→red), shown when value > 100%
            if isPeak {
                ArcShape(
                    start: arcStart + (arcEnd - arcStart) * fractionAt100,
                    end:   arcStart + (arcEnd - arcStart) * fraction
                )
                .stroke(
                    LinearGradient(
                        colors: [.upOrange, .peakRed],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: .peakRed.opacity(0.55), radius: 6)
            }

            // knob body — brushed metal radial gradient
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.329, green: 0.341, blue: 0.400),
                            Color(red: 0.173, green: 0.180, blue: 0.220),
                            Color(red: 0.082, green: 0.086, blue: 0.118),
                        ],
                        center: .init(x: 0.35, y: 0.30),
                        startRadius: 4, endRadius: diameter * 0.6
                    )
                )
                .frame(width: diameter - 24, height: diameter - 24)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.18), Color.black.opacity(0.6)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)

            // indicator line
            Capsule()
                .fill(isPeak ? Color.peakRed : Color.accentCyan)
                .frame(width: 2, height: 14)
                .shadow(color: (isPeak ? Color.peakRed : Color.accentCyan).opacity(0.8), radius: 4)
                .offset(y: -(diameter - 24) / 2 + 10)
                .rotationEffect(indicatorAngle)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if dragStartValue == nil { dragStartValue = value }
                    let dy = Float(drag.translation.height)
                    // 240 px vertical = full 0..1.5 range; up = louder
                    let delta = -dy / 240 * maxValue
                    let next = (dragStartValue ?? value) + delta
                    value = max(0, min(maxValue, next))
                }
                .onEnded { _ in dragStartValue = nil }
        )
        .animation(.easeOut(duration: 0.10), value: value)
    }
}

private struct ArcShape: Shape {
    let start: Double  // degrees
    let end: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2 - 1.5
        // SwiftUI 0° = trailing(right), increases clockwise. Convert from
        // the design convention where 0° = bottom (knob "off") and -135/+135
        // are the arc extremes:
        // Map design angle → SwiftUI angle: swift = design + 90
        p.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(start + 90),
            endAngle: .degrees(end + 90),
            clockwise: false
        )
        return p
    }
}

// MARK: - Power button (replaces Sound toggle)

struct PowerButton: View {
    @Binding var isOn: Bool
    @State private var pressed = false
    private let size: CGFloat = 56
    private let ledSize: CGFloat = 6

    var body: some View {
        ZStack {
            // body
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.294, green: 0.310, blue: 0.369),
                            Color(red: 0.165, green: 0.173, blue: 0.220),
                            Color(red: 0.082, green: 0.086, blue: 0.118),
                        ],
                        center: .init(x: 0.35, y: 0.30),
                        startRadius: 2, endRadius: size * 0.6
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.20), Color.black.opacity(0.7)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.6), radius: 4, y: 2)

            // power glyph
            ZStack {
                Circle()
                    .trim(from: 0.10, to: 0.90)
                    .stroke(
                        isOn ? Color.downGreen.opacity(0.9) : Color.textSecondary,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(90))
                    .frame(width: 18, height: 18)
                Capsule()
                    .fill(isOn ? Color.downGreen.opacity(0.9) : Color.textSecondary)
                    .frame(width: 2, height: 9)
                    .offset(y: -4)
            }
            .shadow(color: isOn ? Color.downGreen.opacity(0.6) : .clear, radius: 4)

            // LED dot near top
            Circle()
                .fill(isOn ? Color.downGreen : Color.white.opacity(0.10))
                .frame(width: ledSize, height: ledSize)
                .shadow(color: isOn ? Color.downGreen : .clear, radius: 5)
                .offset(y: -size/2 + 8)
        }
        .scaleEffect(pressed ? 0.96 : 1.0)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .onTapGesture { isOn.toggle() }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

// MARK: - Keycap button

struct Keycap<Label: View>: View {
    let selected: Bool
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var pressed = false
    @State private var hovering = false

    init(selected: Bool = false,
         width: CGFloat = 88,
         height: CGFloat = 48,
         action: @escaping () -> Void = {},
         @ViewBuilder label: @escaping () -> Label) {
        self.selected = selected
        self.width = width
        self.height = height
        self.action = action
        self.label = label
    }

    var body: some View {
        ZStack {
            // body fill
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: selected
                            ? [.keycapTopL, .keycapTopD]
                            : [Color(red: 0.125, green: 0.133, blue: 0.180),
                               Color(red: 0.082, green: 0.086, blue: 0.118)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            // top highlight (1px white)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: selected
                            ? [Color.white.opacity(0.95), Color.white.opacity(0.0)]
                            : [Color.white.opacity(0.10), Color.black.opacity(0.30)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            // selected accent border + outer glow
            if selected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.accentCyan.opacity(0.55), lineWidth: 1.5)
                    .shadow(color: Color.accentCyan.opacity(0.6), radius: 8)
            }
            label()
                .foregroundColor(selected ? Color.black.opacity(0.85) : .textPrimary)
        }
        .frame(width: width, height: height)
        .scaleEffect(pressed ? 0.96 : 1.0)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .onHover { hovering = $0 }
        .onTapGesture { action() }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .brightness(hovering && !selected ? 0.04 : 0)
    }
}

// MARK: - Top control bar

struct ControlBar: View {
    @ObservedObject var sound: SoundPlayer
    @ObservedObject var store: EventStore
    @Binding var soundEnabled: Bool

    var body: some View {
        HStack(spacing: 28) {
            // Sound power
            VStack(spacing: 4) {
                PowerButton(isOn: $soundEnabled)
                Text("SOUND")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.textSecondary)
            }

            verticalSep

            // Tone selector
            VStack(alignment: .leading, spacing: 6) {
                Text("TONE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.textSecondary)
                HStack(spacing: 6) {
                    ForEach(SoundPlayer.Tone.allCases) { t in
                        Keycap(
                            selected: sound.tone == t,
                            width: 76, height: 40,
                            action: { sound.tone = t },
                            label: {
                                Text(t.rawValue.uppercased())
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .tracking(1)
                            }
                        )
                    }
                }
            }

            verticalSep

            // Volume knob
            VStack(spacing: 4) {
                VolumeKnob(value: $sound.volume, maxValue: SoundPlayer.maxVolume)
                Text("\(Int(sound.volume * 100))%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(sound.volume > 1.0 ? .peakRed : .textPrimary)
                    .monospacedDigit()
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Keycap(width: 72, height: 40, action: { sound.play() }) {
                    Text("TEST")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1)
                }
                Keycap(width: 72, height: 40, action: { store.copyToPasteboard() }) {
                    Text("COPY")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1)
                }
                Keycap(width: 72, height: 40, action: { store.clear() }) {
                    Text("CLEAR")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(1)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.bgCard.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                )
        )
    }

    private var verticalSep: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(width: 1, height: 64)
    }
}

// MARK: - Event row

private let kModGlyphs: [(needle: String, glyph: String)] = [
    ("caps_lock", "⇪"),
    ("shift", "⇧"),
    ("control", "⌃"),
    ("option", "⌥"),
    ("command", "⌘"),
    ("fn", "fn"),
]

struct EventRow: View {
    let event: KeyEvent
    @State private var hovering = false
    @State private var flashOpacity: Double = 1.0

    private var accentColor: Color { event.direction == "down" ? .downGreen : .upOrange }

    private var modGlyphs: [String] {
        let parts = event.flagsText.split(separator: ",").map(String.init)
        return kModGlyphs
            .filter { parts.contains($0.needle) }
            .map { $0.glyph }
    }

    private var jsonKey: String {
        // {"key_code":"left_shift"} → split into "key_code" and "left_shift"
        // for syntax-highlighting. Same for pointing_button.
        let s = event.label
        guard let openQuote = s.firstIndex(of: "\""),
              let colon = s.firstIndex(of: ":") else { return s }
        let keyStart = s.index(after: openQuote)
        let keyEnd = s.index(before: colon)
        guard keyStart < keyEnd else { return s }
        return String(s[keyStart..<keyEnd]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private var jsonValue: String {
        let s = event.label
        guard let colon = s.firstIndex(of: ":") else { return "" }
        let after = s.index(after: colon)
        let inner = String(s[after...])
            .trimmingCharacters(in: CharacterSet(charactersIn: "{}\""))
        return inner
    }

    var body: some View {
        HStack(spacing: 0) {
            // accent bar w/ glow
            Rectangle()
                .fill(accentColor)
                .frame(width: 4, height: 56)
                .shadow(color: accentColor.opacity(0.8 * flashOpacity), radius: 8)
                .opacity(0.6 + 0.4 * flashOpacity)

            // direction
            Text(event.direction)
                .font(.system(size: 22, weight: .light, design: .monospaced))
                .foregroundColor(accentColor)
                .frame(width: 70, alignment: .leading)
                .padding(.leading, 14)

            // code + meta
            VStack(alignment: .leading, spacing: 3) {
                // syntax-highlighted JSON
                HStack(spacing: 0) {
                    Text("{").foregroundColor(.textSecondary)
                    Text("\"").foregroundColor(.textSecondary)
                    Text(jsonKey).foregroundColor(.accentCyan)
                    Text("\"").foregroundColor(.textSecondary)
                    Text(":").foregroundColor(.textSecondary)
                    Text("\"").foregroundColor(.textSecondary)
                    Text(jsonValue).foregroundColor(.textPrimary)
                    Text("\"").foregroundColor(.textSecondary)
                    Text("}").foregroundColor(.textSecondary)
                }
                .font(.system(size: 14, weight: .medium, design: .monospaced))

                HStack(spacing: 8) {
                    if !modGlyphs.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(modGlyphs, id: \.self) { g in
                                Text(g)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .padding(.horizontal, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(Color.white.opacity(0.06))
                                    )
                            }
                        }
                    }
                    if let extra = event.extra {
                        Text(extra)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .padding(.leading, 4)

            Spacer()

            // page / usage on right
            HStack(alignment: .center, spacing: 16) {
                pageOrUsageColumn(label: "PAGE",
                                  value: String(format: "%d (0x%04x)", event.usagePage, event.usagePage))
                pageOrUsageColumn(label: "USAGE",
                                  value: String(format: "%d (0x%04x)", event.usage, event.usage))
            }
            .padding(.trailing, 18)
        }
        .frame(height: 56)
        .background(
            (hovering ? Color.accentCyan.opacity(0.04) : Color.clear)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 0.5)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onAppear {
            // new-row flash (accent bar opacity fade-in)
            flashOpacity = 0
            withAnimation(.easeOut(duration: 0.25)) {
                flashOpacity = 1.0
            }
        }
    }

    private func pageOrUsageColumn(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.textSecondary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.textPrimary)
                .monospacedDigit()
        }
    }
}

// MARK: - Event log container with scanline overlay

struct EventLog: View {
    @ObservedObject var store: EventStore

    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(store.events) { e in
                            EventRow(event: e).id(e.id)
                        }
                    }
                }
                .onChange(of: store.events.count) { _ in
                    if let last = store.events.last {
                        withAnimation(.linear(duration: 0.08)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            // CRT scanline (very subtle)
            ScanlineOverlay()
                .allowsHitTesting(false)
        }
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.031, green: 0.035, blue: 0.102),
                        Color(red: 0.055, green: 0.059, blue: 0.141),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                // very faint noise texture via overlapping circles? Simpler: omit.
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
        )
    }
}

struct ScanlineOverlay: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/60.0)) { context in
            GeometryReader { geo in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let cycle: Double = 6.0
                let progress = (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
                let y = geo.size.height * (1.0 - progress)
                LinearGradient(
                    colors: [.clear, Color.accentCyan.opacity(0.15), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 60)
                .offset(y: y - 30)
                .blendMode(.plusLighter)
            }
        }
    }
}

// MARK: - Root

struct ContentView: View {
    @StateObject private var store = EventStore()
    @StateObject private var sound = SoundPlayer()
    @StateObject private var monitor = KeyMonitor()
    @State private var soundEnabled = true

    var body: some View {
        ZStack {
            WindowBackground()

            VStack(spacing: 14) {
                // Top spacer for hidden title bar drag area (28pt)
                Color.clear.frame(height: 22)

                ControlBar(sound: sound, store: store, soundEnabled: $soundEnabled)
                    .padding(.horizontal, 18)

                HStack {
                    Text("KEYBOARD & POINTING EVENTS")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("\(store.events.count) events")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, 22)

                EventLog(store: store)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            }
        }
        .frame(minWidth: 940, minHeight: 600)
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
            ContentView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}
