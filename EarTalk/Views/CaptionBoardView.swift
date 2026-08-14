import SwiftUI

/// Two-sided board. They speak on the left, I speak on the right.
/// Owner holds the phone: translation toward you lands on the right,
/// translation toward them lands on the left. The other side is the original.
struct CaptionBoardView: View {
    @EnvironmentObject private var session: SessionController

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                statusRow

                HStack(alignment: .top, spacing: 0) {
                    column(
                        title: "They speak",
                        language: SpokenLanguage.named(session.settings.theirLanguage).name,
                        text: theirSideText,
                        emphasized: session.captionTurn?.direction == .meToThem
                    )

                    Divider()

                    column(
                        title: "I speak",
                        language: SpokenLanguage.named(session.settings.myLanguage).name,
                        text: mySideText,
                        emphasized: session.captionTurn?.direction == .themToMe
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
            .navigationTitle("EarTalk")
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

    private var theirSideText: String {
        guard let turn = session.captionTurn else { return "" }
        return turn.direction == .themToMe ? turn.sourceText : turn.translatedText
    }

    private var mySideText: String {
        guard let turn = session.captionTurn else { return "" }
        return turn.direction == .themToMe ? turn.translatedText : turn.sourceText
    }

    private var statusRow: some View {
        HStack {
            if session.phase.isCapturing || session.isConversationLive {
                Label("Listening", systemImage: "mic.fill")
                    .foregroundStyle(Color.red)
            } else if session.player.isPlaying {
                Label("Speaking", systemImage: "speaker.wave.2.fill")
                    .foregroundStyle(Color.accentColor)
            }
            Spacer()
            Text(session.headphonesWorn ? "AirPods in" : "AirPods out")
                .foregroundStyle(session.headphonesWorn ? Color.secondary : Color.orange)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func column(title: String, language: String, text: String, emphasized: Bool) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(language)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1.0)

            Text(text.isEmpty ? " " : text)
                .font(.system(size: emphasized ? 36 : 28, weight: .bold))
                .minimumScaleFactor(0.28)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
