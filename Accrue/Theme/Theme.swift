import SwiftUI

/// Colour tokens for the two themes Li picked: D1 Lime night (default) and L3 Sage and lime.
struct Palette: Sendable {
    var background: Color
    var card: Color
    var raised: Color
    var line: Color
    var text: Color
    var secondary: Color
    var accentFill: Color
    var accentText: Color
    var onAccent: Color
    var accentSoft: Color
    var warmup: Color
    var danger: Color
    var cardio: Color

    static let limeNight = Palette(
        background: Color(hex: 0x0E0F12),
        card: Color(hex: 0x1A1C21),
        raised: Color(hex: 0x24272D),
        line: Color(hex: 0x3A3E46),
        text: Color(hex: 0xF2F3F5),
        secondary: Color(hex: 0xA2A8B4),
        accentFill: Color(hex: 0xC6F432),
        accentText: Color(hex: 0xC6F432),
        onAccent: Color(hex: 0x0E0F12),
        accentSoft: Color(hex: 0x2F3A12),
        warmup: Color(hex: 0xFFB547),
        danger: Color(hex: 0xFF5A4E),
        cardio: Color(hex: 0x5BC8FF)
    )

    static let sageAndLime = Palette(
        background: Color(hex: 0xFAFBF8),
        card: Color(hex: 0xFFFFFF),
        raised: Color(hex: 0xF0F3EC),
        line: Color(hex: 0xD5DCCD),
        text: Color(hex: 0x1A2116),
        secondary: Color(hex: 0x5F6B57),
        accentFill: Color(hex: 0xC6F432),
        accentText: Color(hex: 0x4D7C0F),
        onAccent: Color(hex: 0x1A2116),
        accentSoft: Color(hex: 0xEEF9D6),
        warmup: Color(hex: 0xB86E00),
        danger: Color(hex: 0xD63A2F),
        cardio: Color(hex: 0x1F7FB0)
    )
}

extension EnvironmentValues {
    @Entry var palette: Palette = .limeNight
}

/// The Appearance setting in You.
enum Appearance: String, CaseIterable, Identifiable {
    case dark, light, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "Match iPhone"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

enum SettingsKey {
    static let appearance = "appearance"
    static let weightUnit = "weightUnit"
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: Type

extension Font {
    /// Barlow Condensed ExtraBold, for titles and big numbers. Scales with Dynamic Type.
    static func display(_ size: CGFloat, relativeTo style: Font.TextStyle = .largeTitle) -> Font {
        .custom("BarlowCondensed-ExtraBold", size: size, relativeTo: style)
    }

    /// Barlow Condensed Bold, for numbers inside controls.
    static func number(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("BarlowCondensed-Bold", size: size, relativeTo: style)
    }

    /// Inter, the body face.
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        let name = switch weight {
        case .medium: "Inter-Medium"
        case .semibold: "Inter-SemiBold"
        case .bold: "Inter-Bold"
        case .heavy, .black: "Inter-ExtraBold"
        default: "Inter-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }
}

// MARK: Shared styles

struct CardBackground: ViewModifier {
    @Environment(\.palette) private var palette
    var radius: CGFloat = 20
    var color: Color?

    func body(content: Content) -> some View {
        content.background(color ?? palette.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func card(radius: CGFloat = 20, color: Color? = nil) -> some View {
        modifier(CardBackground(radius: radius, color: color))
    }

    /// Small upper-case label above a group ("FAVORITES · BACK").
    func sectionLabel() -> some View {
        modifier(SectionLabel())
    }
}

struct SectionLabel: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .font(.inter(11, .bold, relativeTo: .caption))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(palette.secondary)
    }
}

/// The big lime action ("Log set 3 · 100 × 10").
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(16, .heavy))
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(palette.onAccent)
            .background(palette.accentFill.opacity(isEnabled ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Outlined pill ("Start Pull workout").
struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(15, .heavy))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(palette.accentText)
            .overlay(Capsule().strokeBorder(palette.accentText, lineWidth: 2))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Grey pill ("Other", "+ 1 set").
struct SoftButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.inter(15, .bold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(palette.text)
            .background(palette.raised, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    static var outline: OutlineButtonStyle { OutlineButtonStyle() }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var soft: SoftButtonStyle { SoftButtonStyle() }
}

/// A row of options in a rounded track, the selected one filled.
struct SegmentPicker<Value: Hashable>: View {
    @Environment(\.palette) private var palette
    let options: [(Value, String)]
    @Binding var selection: Value
    var filled = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Button {
                    selection = value
                } label: {
                    Text(label)
                        .font(.inter(13, .heavy, relativeTo: .subheadline))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .foregroundStyle(on ? (filled ? palette.onAccent : palette.background) : palette.secondary)
                        .background(on ? (filled ? palette.accentFill : palette.text) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
