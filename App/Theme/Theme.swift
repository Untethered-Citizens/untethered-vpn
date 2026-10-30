import SwiftUI

// The brand theme from design round 1: colours (Theme.xcassets, light and
// dark), type, and the button, row and toggle styles. A focused control fills
// solid green (plum for destructive, D37), scales up and lifts (D38).

/// Colour tokens. Each has a light and a dark value in Theme.xcassets.
enum UTColor {
    static let background = Color("UTBackground")
    static let panel = Color("UTPanel")
    static let ink = Color("UTInk")
    static let muted = Color("UTMuted")
    static let rule = Color("UTRule")
    static let green = Color("UTGreen")
    static let greenSoft = Color("UTGreenSoft")
    /// A fill only, never text; ochre text uses `ochreInk`.
    static let ochre = Color("UTOchre")
    static let ochreInk = Color("UTOchreInk")
    /// Failures and destructive actions (D37).
    static let plum = Color("UTPlum")
    /// Text on a focused (solid) fill.
    static let onAccent = Color("UTOnAccent")
}

/// Sizes in points at 1920 × 1080.
enum UTMetrics {
    /// tvOS already insets the sides by 80 pt; the design uses 90.
    static let extraSideInset: CGFloat = 10
    static let buttonHeight: CGFloat = 104
    static let heroButtonHeight: CGFloat = 124
    static let rowMinHeight: CGFloat = 120
    static let panelRadius: CGFloat = 48
    static let cardRadius: CGFloat = 32
    static let rowRadius: CGFloat = 28
    static let focusScale: CGFloat = 1.08
    static let rowFocusScale: CGFloat = 1.04
}

// MARK: - Type

/// Barlow for text, Barlow Condensed for section titles and numbers. Each
/// size is relative to a text style, so it follows the system text size.
/// The fonts are in Fonts/ and listed under `UIAppFonts`; a name that
/// doesn't match falls back to the system font, so a test checks them.
enum UTFont {
    enum Weight: CaseIterable { case regular, medium, semibold, bold }

    static func barlow(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(barlowName(weight), size: size, relativeTo: style)
    }

    static func condensed(_ size: CGFloat, _ weight: Weight = .semibold, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(condensedName(weight), size: size, relativeTo: style)
    }

    static func barlowName(_ weight: Weight) -> String {
        switch weight {
        case .regular: "Barlow-Regular"
        case .medium: "Barlow-Medium"
        case .semibold: "Barlow-SemiBold"
        case .bold: "Barlow-Bold"
        }
    }

    /// Barlow Condensed has no Regular here; it uses Medium.
    static func condensedName(_ weight: Weight) -> String {
        switch weight {
        case .regular, .medium: "BarlowCondensed-Medium"
        case .semibold: "BarlowCondensed-SemiBold"
        case .bold: "BarlowCondensed-Bold"
        }
    }

    /// Every font name the theme can ask for.
    static var allNames: Set<String> {
        Set(Weight.allCases.flatMap { [barlowName($0), condensedName($0)] })
    }
}

extension Font {
    static let utDisplay = UTFont.barlow(96, .semibold, relativeTo: .largeTitle)
    static let utTitle = UTFont.barlow(76, .semibold, relativeTo: .largeTitle)
    static let utTitle2 = UTFont.barlow(56, .semibold, relativeTo: .title)
    static let utHeadline = UTFont.barlow(40, .semibold, relativeTo: .headline)
    static let utRowTitle = UTFont.barlow(36, .semibold, relativeTo: .headline)
    static let utBody = UTFont.barlow(34, relativeTo: .body)
    static let utCaption = UTFont.barlow(29, relativeTo: .caption)
    static let utButton = UTFont.barlow(38, .semibold, relativeTo: .body)
    static let utHeroButton = UTFont.barlow(50, .semibold, relativeTo: .title2)
    static let utStatus = UTFont.barlow(46, .semibold, relativeTo: .title2)
    static let utStatusSmall = UTFont.barlow(29, .semibold, relativeTo: .caption)
    static let utSection = UTFont.condensed(36, relativeTo: .headline)
    /// Live numbers; use with `.monospacedDigit()`.
    static let utNumber = UTFont.condensed(104, relativeTo: .largeTitle)
    static let utNumberUnit = UTFont.condensed(44, relativeTo: .title2)
    static let utCountdown = UTFont.condensed(46, relativeTo: .title2)
}

// MARK: - Focus

extension EnvironmentValues {
    /// True inside a themed button or row while it has focus, so its label
    /// can switch to `onAccent`.
    @Entry var utFocused = false
}

/// The focused control's scale, lift shadow and animation (D38). Reduce
/// Motion turns off the animation.
private struct UTFocusLift: ViewModifier {
    let focused: Bool
    let scale: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.utFocused, focused)
            .scaleEffect(focused ? scale : 1)
            // One shadow for the whole control, not one behind each piece of text
            .compositingGroup()
            .shadow(color: focused ? shadow : .clear, radius: 22, y: focused ? 22 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: focused)
    }

    private var shadow: Color {
        scheme == .dark ? .black.opacity(0.6) : Color(red: 30 / 255, green: 42 / 255, blue: 35 / 255).opacity(0.26)
    }
}

// MARK: - Buttons

/// A pill button. Unfocused: primary has a soft green fill, secondary and
/// destructive a grey one (destructive with plum text). Focused: solid green,
/// or plum for destructive.
struct UTButtonStyle: ButtonStyle {
    enum Role { case primary, secondary, destructive }
    enum Size { case regular, hero }

    var role: Role = .secondary
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        UTButtonBody(configuration: configuration, role: role, size: size)
    }
}

private struct UTButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let role: UTButtonStyle.Role
    let size: UTButtonStyle.Size
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let hero = size == .hero
        configuration.label
            .font(hero ? .utHeroButton : .utButton)
            .foregroundStyle(text)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, hero ? 72 : 44)
            .frame(minWidth: hero ? 460 : nil, minHeight: hero ? UTMetrics.heroButtonHeight : UTMetrics.buttonHeight)
            .background(Capsule().fill(fill))
            .opacity(isEnabled ? 1 : 0.5)
            .modifier(UTFocusLift(focused: isFocused, scale: UTMetrics.focusScale))
            .opacity(configuration.isPressed ? 0.88 : 1)
    }

    private var fill: Color {
        switch (role, isFocused) {
        case (.destructive, true): UTColor.plum
        case (_, true): UTColor.green
        case (.primary, false): UTColor.greenSoft
        default: UTColor.rule
        }
    }

    private var text: Color {
        if isFocused { return UTColor.onAccent }
        return role == .destructive ? UTColor.plum : UTColor.ink
    }
}

extension ButtonStyle where Self == UTButtonStyle {
    static var utPrimary: UTButtonStyle { UTButtonStyle(role: .primary) }
    static var utHero: UTButtonStyle { UTButtonStyle(role: .primary, size: .hero) }
    static var utSecondary: UTButtonStyle { UTButtonStyle() }
    static var utDestructive: UTButtonStyle { UTButtonStyle(role: .destructive) }
}

// MARK: - Rows

/// A full-width row: the panel colour with a thin outline, solid green when
/// focused.
struct UTRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        UTRowBody(configuration: configuration)
    }
}

private struct UTRowBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: UTMetrics.rowRadius, style: .continuous)
        configuration.label
            .foregroundStyle(isFocused ? UTColor.onAccent : UTColor.ink)
            .padding(.horizontal, 40)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, minHeight: UTMetrics.rowMinHeight, alignment: .leading)
            .background(shape.fill(isFocused ? UTColor.green : UTColor.panel))
            .overlay(shape.strokeBorder(isFocused ? .clear : UTColor.rule, lineWidth: 2))
            .modifier(UTFocusLift(focused: isFocused, scale: UTMetrics.rowFocusScale))
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

extension ButtonStyle where Self == UTRowButtonStyle {
    static var utRow: UTRowButtonStyle { UTRowButtonStyle() }
}

/// A large choice card, like the two on Add Profile: a panel with a rule
/// outline that fills green and lifts when focused, like a row.
struct UTCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        UTCardBody(configuration: configuration)
    }
}

private struct UTCardBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: UTMetrics.cardRadius, style: .continuous)
        configuration.label
            .foregroundStyle(isFocused ? UTColor.onAccent : UTColor.ink)
            .background(shape.fill(isFocused ? UTColor.green : UTColor.panel))
            .overlay(shape.strokeBorder(isFocused ? .clear : UTColor.rule, lineWidth: 2))
            .modifier(UTFocusLift(focused: isFocused, scale: UTMetrics.rowFocusScale))
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

extension ButtonStyle where Self == UTCardButtonStyle {
    static var utCard: UTCardButtonStyle { UTCardButtonStyle() }
}

/// A text field as a row: the label with its hint (or problem, in plum)
/// on the left, the field on the right. Selecting it opens the tvOS
/// keyboard. The field is the focus target, so the row follows `focused`.
struct UTFieldRow<Field: View>: View {
    let label: String
    let note: String
    var isProblem = false
    let focused: Bool
    @ViewBuilder let field: Field

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: UTMetrics.rowRadius, style: .continuous)
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.utRowTitle)
                Group {
                    if isProblem {
                        Label(note, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(focused ? UTColor.onAccent : UTColor.plum)
                    } else {
                        Text(note)
                            .foregroundStyle(focused ? UTColor.onAccent : UTColor.muted)
                    }
                }
                .font(.utCaption)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 560, alignment: .leading)
            .foregroundStyle(focused ? UTColor.onAccent : UTColor.ink)
            // tvOS draws its own platter behind a text field and picks the
            // text colour to suit it, so the field keeps the system colours
            field
                .font(UTFont.barlow(34, .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, minHeight: UTMetrics.rowMinHeight, alignment: .leading)
        .background(shape.fill(focused ? UTColor.green : UTColor.panel))
        .overlay(shape.strokeBorder(focused ? .clear : (isProblem ? UTColor.plum : UTColor.rule), lineWidth: 2))
        .modifier(UTFocusLift(focused: focused, scale: UTMetrics.rowFocusScale))
    }
}

/// Icon, title, optional subtitle and a chevron, for Settings-style rows.
struct UTRowLabel: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    @Environment(\.utFocused) private var focused

    var body: some View {
        HStack(spacing: 28) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .medium))
                    .frame(width: 52)
                    .foregroundStyle(focused ? UTColor.onAccent : UTColor.green)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.utRowTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(.utCaption)
                        .foregroundStyle(focused ? UTColor.onAccent : UTColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            Image(systemName: "chevron.right")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(focused ? UTColor.onAccent : UTColor.muted)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Toggle

/// A toggle as a row, with "On" or "Off" beside the switch.
struct UTToggleStyle: ToggleStyle {
    var systemImage: String?

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            UTToggleLabel(configuration: configuration, systemImage: systemImage)
        }
        .buttonStyle(.utRow)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private struct UTToggleLabel: View {
    let configuration: ToggleStyleConfiguration
    let systemImage: String?
    @Environment(\.utFocused) private var focused

    var body: some View {
        let on = configuration.isOn
        HStack(spacing: 28) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(focused ? UTColor.onAccent : UTColor.green)
                    .accessibilityHidden(true)
            }
            configuration.label.font(.utRowTitle)
            Spacer(minLength: 16)
            Text(on ? "On" : "Off")
                .font(UTFont.barlow(32, .semibold))
                .foregroundStyle(focused ? UTColor.onAccent : (on ? UTColor.green : UTColor.muted))
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(focused ? UTColor.onAccent : (on ? UTColor.green : UTColor.rule))
                Circle()
                    .fill(focused ? UTColor.green : (on ? UTColor.panel : UTColor.muted))
                    .padding(6)
            }
            .frame(width: 96, height: 54)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Symbols

/// One of the app's own symbols from Theme.xcassets (template images, so
/// they take the text colour). Decorative: the text beside it says what it is.
struct UTSymbol: View {
    let name: String
    var size: CGFloat = 40

    init(_ name: String, size: CGFloat = 40) {
        self.name = name
        self.size = size
    }

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A whole-screen message in place of content: a large symbol, a title,
/// the explanation and the actions. For the empty home screen and the
/// phone import's end states.
struct UTMessageScreen<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = UTColor.muted
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: 40) {
            UTSymbol(symbol, size: 160)
                .foregroundStyle(tint)
            VStack(spacing: 20) {
                Text(title)
                    .font(.utTitle2)
                Text(message)
                    .foregroundStyle(UTColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            HStack(spacing: 40) {
                actions
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: 1100)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Surfaces

extension View {
    /// A screen's ground and default text. Put it on each screen's root.
    func utScreen() -> some View {
        padding(.horizontal, UTMetrics.extraSideInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(UTColor.background.ignoresSafeArea())
            .foregroundStyle(UTColor.ink)
            .font(.utBody)
    }

    /// A content panel: the hero card, stats, review columns, help.
    func utPanel(radius: CGFloat = UTMetrics.panelRadius, padding: CGFloat = 56) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(UTColor.panel))
    }
}

/// A section title in Barlow Condensed, muted.
struct UTSectionHeader: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.utSection)
            .foregroundStyle(UTColor.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A live stat: its label, then big numbers with smaller units, as in
/// "1 hour 12 minutes".
struct UTStat: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(label)
                .font(UTFont.barlow(32))
                .foregroundStyle(UTColor.muted)
            styled
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        // Take the whole cell, so the numbers shrink only when they must
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var styled: Text {
        StatsFormat.parts(value).enumerated().reduce(Text(verbatim: "")) { text, item in
            let (index, part) = item
            let number = Text(verbatim: part.number).font(.utNumber).foregroundStyle(UTColor.ink)
            let unit = Text(verbatim: part.unit.isEmpty ? "" : " " + part.unit)
                .font(.utNumberUnit).foregroundStyle(UTColor.muted)
            return Text("\(text)\(index == 0 ? "" : " ")\(number)\(unit)")
        }
    }
}
