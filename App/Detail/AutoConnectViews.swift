import SwiftUI

/// The marker beside a profile that has Connect Automatically on.
struct AutoConnectMarker: View {
    var compact = false

    var body: some View {
        // A Label crowds the icon against the text on a focused row
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .accessibilityHidden(true)
            Text("Connects automatically")
        }
        .font(compact ? .callout : .title3)
        .foregroundStyle(.secondary)
    }
}

extension View {
    /// Says when connecting or disconnecting turned Connect Automatically
    /// off. Several at once are shown together.
    func autoConnectNotes(_ notes: Binding<[AutoConnect.TurnedOff]>) -> some View {
        alert(
            AutoConnect.TurnedOff.title,
            isPresented: Binding(get: { !notes.wrappedValue.isEmpty }, set: { if !$0 { notes.wrappedValue = [] } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notes.wrappedValue.map(\.message).joined(separator: "\n\n"))
        }
    }
}
