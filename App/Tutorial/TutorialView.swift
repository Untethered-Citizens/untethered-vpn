import SwiftUI

/// How It Works: six cards with Back and Next, and Skip until the last.
/// Offered on a first launch with no profiles, and opened from Settings and
/// the empty home screen. Menu closes it, like Skip.
struct TutorialView: View {
    var startsOn: TutorialCard = .overview
    let done: () -> Void

    @State private var card: TutorialCard = .overview
    @State private var forward = true
    @FocusState private var focus: Control?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Control { case skip, back, next }

    var body: some View {
        VStack(alignment: .leading, spacing: 48) {
            Text(card.title)
                .font(.utTitle)
                .accessibilityAddTraits(.isHeader)
            TutorialCardContent(card: card)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .id(card)
        .transition(transition)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom) { controls }
        .padding(80)
        .utScreen()
        .onExitCommand(perform: done)
        .onAppear { card = startsOn }
        .defaultFocus($focus, .next)
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                           removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 40) {
            Button("Skip", action: done)
                .buttonStyle(.utSecondary)
                .focused($focus, equals: .skip)
                .opacity(isLast ? 0 : 1)
                .disabled(isLast)
            Spacer()
            dots
            Spacer()
            Button("Back") { move(by: -1) }
                .buttonStyle(.utSecondary)
                .focused($focus, equals: .back)
                .disabled(isFirst)
            Button(isLast ? "Done" : "Next") {
                if isLast { done() } else { move(by: 1) }
            }
            .buttonStyle(.utPrimary)
            .focused($focus, equals: .next)
        }
        .padding(.top, 32)
        .focusSection()
    }

    private var dots: some View {
        HStack(spacing: 18) {
            ForEach(TutorialCard.allCases) { item in
                Circle()
                    .fill(item == card ? UTColor.green : UTColor.rule)
                    .frame(width: 18, height: 18)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Card \(card.rawValue + 1) of \(TutorialCard.allCases.count)")
    }

    private var isFirst: Bool { card == TutorialCard.allCases.first }
    private var isLast: Bool { card == TutorialCard.allCases.last }

    private func move(by step: Int) {
        guard let next = TutorialCard(rawValue: card.rawValue + step) else { return }
        forward = step > 0
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.35)) {
            card = next
        }
        if next == TutorialCard.allCases.first { focus = .next }
        AccessibilityNotification.Announcement("\(next.title). Card \(next.rawValue + 1) of \(TutorialCard.allCases.count).").post()
    }
}

/// A request to show How It Works, for `fullScreenCover(item:)`.
struct TutorialRequest: Identifiable {
    let id = UUID()
    var startsOn: TutorialCard = .overview
}
