import SwiftUI

/// Changing only a profile's name: one field, its problem if any, and
/// Save or Cancel. Used by Rename on Details and the home screen, and by
/// the QR import's review before anything is saved.
struct RenameView: View {
    let otherNames: [String]
    /// Applies the new name; an error's message is shown and the sheet stays.
    let save: (String) async throws -> Void
    let done: () -> Void

    @State private var name: String
    @State private var changed = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    init(name: String, otherNames: [String], save: @escaping (String) async throws -> Void, done: @escaping () -> Void) {
        self.otherNames = otherNames
        self.save = save
        self.done = done
        _name = State(initialValue: name)
        // A name that's already a problem (an import's duplicate) says so at once
        _changed = State(initialValue: ProfileName.problem(name, otherNames: otherNames) != nil)
    }

    var body: some View {
        let problem = ProfileName.problem(name, otherNames: otherNames)
        VStack(alignment: .leading, spacing: 48) {
            Text("Rename Profile")
                .font(.utTitle2)
                .accessibilityAddTraits(.isHeader)

            UTFieldRow(label: "Name",
                       note: changed ? problem ?? Self.hint : Self.hint,
                       isProblem: changed && problem != nil,
                       focused: fieldFocused) {
                TextField("Name", text: $name, prompt: Text("Profile name, such as Home"))
                    .focused($fieldFocused)
                    .onChange(of: name) { changed = true }
            }

            HStack(spacing: 28) {
                Button {
                    submit(problem: problem)
                } label: {
                    HStack(spacing: 16) {
                        if isSaving { ProgressView() }
                        Text(isSaving ? "Saving…" : "Save")
                    }
                }
                .buttonStyle(.utPrimary)
                .disabled(isSaving)
                Button("Cancel", role: .cancel, action: done)
                    .buttonStyle(.utSecondary)
                    .disabled(isSaving)
            }
        }
        .frame(maxWidth: 1300, alignment: .leading)
        .padding(80)
        .utScreen()
        .alert(
            "Not renamed",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private static let hint = "Shown on the home screen. The profile's settings and keys don't change."

    private func submit(problem: String?) {
        changed = true
        if problem != nil {
            fieldFocused = true
            return
        }
        isSaving = true
        Task {
            do {
                try await save(ProfileName.cleaned(name))
                done()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

/// A request to rename a profile, for `sheet(item:)`.
struct RenameRequest: Identifiable {
    let id: UUID
    let name: String
}
