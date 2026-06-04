import SwiftUI

/// Corner-pinned Kongle that opens the helper modal when clicked. Cycles
/// through expressions on a slow tick so he feels alive in peripheral
/// vision without becoming a distraction. The modal he opens is
/// `KongleHelperModal`; functionality behind the menu options is still
/// stubbed.
struct KongleHelper: View {
    @Environment(\.palette) private var p
    @Environment(ModalState.self) private var modal

    @State private var expressionIndex: Int = 0

    /// Two minutes between expression swaps — slow enough that it reads
    /// as ambient mood rather than animation.
    private static let cycleInterval: TimeInterval = 120

    /// Expression rotation. Waving leads so a fresh launch greets the user;
    /// the rest is a loose loop through Kongle's working/idle moods.
    private static let expressions: [String] = [
        "KongleWaving",
        "KongleHappy",
        "KongleFocused",
        "KongleWriting",
        "KongleCoffee",
        "KongleWinking",
        "KongleSleeping",
        "KongleCelebrating",
    ]

    private var currentExpression: String {
        Self.expressions[expressionIndex % Self.expressions.count]
    }

    var body: some View {
        // The SVG renders inside a WKWebView, which would swallow clicks;
        // overlay a transparent Button so taps reach SwiftUI cleanly.
        AnimatedSVG(assetName: currentExpression)
            .frame(width: 120, height: 120)
            .allowsHitTesting(false)
            .overlay {
                Button {
                    modal.kongleHelperOpen.toggle()
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Talk to Kongle")
            }
            .task(id: expressionIndex) {
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.cycleInterval * 1_000_000_000))
                    expressionIndex = (expressionIndex + 1) % Self.expressions.count
                } catch {
                    // Cancellation only — .task tears the Task down on
                    // view dismissal or id change; nothing to recover.
                }
            }
    }
}
