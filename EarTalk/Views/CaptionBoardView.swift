import SwiftUI

/// Face-to-face board. Top is upside-down for the person across from you.
/// The one receiving the translation gets 3/5. The original is 2/5 for a check.
struct CaptionBoardView: View {
    @EnvironmentObject private var session: SessionController

    private var towardMe: Bool {
        session.captionTurn?.direction != .meToThem
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let height = geo.size.height
                let topShare: CGFloat = towardMe ? 0.4 : 0.6
                VStack(spacing: 0) {
                    pane(
                        title: towardMe ? "They said" : "They hear",
                        language: SpokenLanguage.named(session.settings.theirLanguage).name,
                        text: topText,
                        big: !towardMe
                    )
                    .frame(height: height * topShare)
                    .rotationEffect(.degrees(180))

                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 1)

                    pane(
                        title: towardMe ? "You hear" : "You said",
                        language: SpokenLanguage.named(session.settings.myLanguage).name,
                        text: bottomText,
                        big: towardMe
                    )
                    .frame(height: height * (1 - topShare))
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(session.isConversationLive ? "Listening" : "EarTalk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stop", role: .destructive) {
                        session.stopSession()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        session.dismissCaption()
                    }
                    .fontWeight(.semibold)
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private var topText: String {
        guard let turn = session.captionTurn else { return "" }
        return towardMe ? turn.sourceText : turn.translatedText
    }

    private var bottomText: String {
        guard let turn = session.captionTurn else { return "" }
        return towardMe ? turn.translatedText : turn.sourceText
    }

    private func pane(title: String, language: String, text: String, big: Bool) -> some View {
        VStack(spacing: 8) {
            Text("\(title) · \(language)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text(text.isEmpty ? " " : text)
                .font(.system(size: big ? 44 : 28, weight: .bold))
                .minimumScaleFactor(0.22)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 16)
                .overlay {
                    if text.isEmpty {
                        ProgressView()
                    }
                }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
