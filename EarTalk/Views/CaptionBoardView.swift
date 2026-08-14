import SwiftUI

/// Huge text for the person in front. They can read while Grok speaks their language.
struct CaptionBoardView: View {
    let turn: ConversationTurn
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(SpokenLanguage.named(turn.targetLanguage).name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1.2)

                Spacer(minLength: 8)

                Text(turn.translatedText)
                    .font(.system(size: 44, weight: .bold))
                    .minimumScaleFactor(0.28)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 8)

                Text(turn.sourceText)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal)

                Spacer(minLength: 8)
            }
            .padding()
            .navigationTitle("Show them")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
