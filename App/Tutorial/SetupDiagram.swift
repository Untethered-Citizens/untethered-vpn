import SwiftUI

/// The typical setup, for the tutorial's first card: the Apple TV away from
/// home, an encrypted tunnel across the internet, the home router and the
/// user's own WireGuard server, then the streaming apps. Green is this app;
/// ochre with a dashed outline is the part the user sets up. Drawn with
/// shapes and symbols, so it's sharp at 4K and follows light and dark.
struct SetupDiagram: View {
    nonisolated static let symbols = ["appletv", "lock.fill", "wifi.router", "server.rack", "play.tv"]
    static let accessibilityText = "An Apple TV away from home connects through an encrypted tunnel to a WireGuard server at your home. Streaming apps then see your home address. The server isn't included with this app."

    var body: some View {
        VStack(spacing: 36) {
            HStack(alignment: .center, spacing: 0) {
                place("Away") {
                    node("appletv", "Apple TV", "Untethered VPN", style: .app)
                }
                tunnel
                place("Home") {
                    HStack(spacing: 0) {
                        node("wifi.router", "Home router", "Forwards a UDP port", style: .plain)
                        arrow.frame(width: 56)
                        node("server.rack", "WireGuard server", "Yours, not included", style: .yours)
                    }
                }
                arrow.frame(width: 64)
                node("play.tv", "Streaming apps", "See your home address", style: .plain)
            }
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityText)
    }

    // MARK: - Pieces

    private enum NodeStyle { case app, yours, plain }

    private func node(_ symbol: String, _ title: String, _ subtitle: String, style: NodeStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 52, weight: .medium))
                .frame(height: 64)
                .foregroundStyle(style == .yours ? UTColor.ochreInk : UTColor.green)
            Text(title)
                .font(UTFont.barlow(30, .semibold, relativeTo: .headline))
            Text(subtitle)
                .font(UTFont.barlow(24, relativeTo: .caption))
                .foregroundStyle(style == .yours ? UTColor.ochreInk : UTColor.muted)
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.7)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .frame(width: 250)
        .background(shape.fill(fill(style)))
        .overlay {
            switch style {
            case .app: shape.strokeBorder(UTColor.green, lineWidth: 3)
            case .yours: shape.strokeBorder(UTColor.ochreInk, style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
            case .plain: shape.strokeBorder(UTColor.rule, lineWidth: 2)
            }
        }
    }

    private func fill(_ style: NodeStyle) -> Color {
        switch style {
        case .app: UTColor.greenSoft
        case .yours: UTColor.ochre.opacity(0.25)
        case .plain: UTColor.background
        }
    }

    /// A labelled area (Away, Home) around one or more nodes.
    private func place(_ name: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 16) {
            Text(name)
                .font(.utSection)
                .foregroundStyle(UTColor.muted)
            content()
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(UTColor.panel))
    }

    private var tunnel: some View {
        VStack(spacing: 12) {
            Text("Encrypted tunnel")
                .font(UTFont.barlow(26, .semibold, relativeTo: .caption))
            HStack(spacing: 10) {
                dashes
                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(UTColor.green)
                dashes
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(UTColor.green)
            }
            Text("across the internet")
                .font(UTFont.barlow(24, relativeTo: .caption))
                .foregroundStyle(UTColor.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

    private var dashes: some View {
        Line()
            .stroke(UTColor.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [12, 10]))
            .frame(height: 5)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(UTColor.muted)
    }

    private var legend: some View {
        HStack(spacing: 56) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 6).fill(UTColor.greenSoft)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(UTColor.green, lineWidth: 3))
                    .frame(width: 32, height: 32)
                Text("This app")
            }
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 6).fill(UTColor.ochre.opacity(0.25))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(UTColor.ochreInk, style: StrokeStyle(lineWidth: 3, dash: [6, 4])))
                    .frame(width: 32, height: 32)
                Text("You set this up once. Many guides exist.")
            }
        }
        .font(.utCaption)
        .foregroundStyle(UTColor.muted)
    }
}

/// A horizontal line through the middle of its frame.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
