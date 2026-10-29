import SwiftUI

/// A profile's export: the config with keys and the server's address hidden,
/// and a QR code of the same text for a phone to copy. Nothing is sent
/// anywhere; the text only leaves the TV if someone scans it.
struct ExportView: View {
    let export: ProfileExport
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            Text("Export “\(export.name)”")
                .font(.title2.bold())

            HStack(alignment: .top, spacing: 72) {
                VStack(alignment: .leading, spacing: 28) {
                    Text(export.text)
                        .font(.callout.monospaced())
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Label {
                        Text(ProfileExport.hiddenNote)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "eye.slash")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                VStack(spacing: 24) {
                    QRCodeTile(text: export.text, size: 360,
                               failureText: "The code couldn't be drawn.",
                               accessibilityLabel: "QR code of the exported profile")
                    Text(ProfileExport.qrHint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: 400)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("Done", action: done)
                .font(.title3)
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand(perform: done)
    }
}
