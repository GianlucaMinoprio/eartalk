import SwiftUI

/// Native iOS. Status first. Languages. One Listen. Caption is the product.
struct RootView: View {
    @EnvironmentObject private var session: SessionController
    @State private var showSettings = false
    @State private var showSuperGrok = false

    var body: some View {
        NavigationStack {
            List {
                statusSection
                if !session.isLiveTurn {
                    languagesSection
                }
                nowSection
                if !session.isLiveTurn {
                    historySection
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(session.phase == .playingSpeaker ? "Show them" : "EarTalk")
            .navigationBarTitleDisplayMode(session.isLiveTurn ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    if session.showsStop {
                        Button("Stop", role: .destructive) {
                            session.stopSession()
                        }
                    }

                    Spacer()

                    Menu {
                        Button("They talk", systemImage: "ear") {
                            session.startHearingThem()
                        }
                        Button("I talk", systemImage: "mic") {
                            session.startHearingMe()
                        }
                    } label: {
                        Label("Force", systemImage: "hand.point.up.left")
                    }
                    .disabled(session.isBusy && !session.phase.isCapturing)

                    Button {
                        if session.phase.isCapturing {
                            session.stopSession()
                        } else {
                            session.startListening()
                        }
                    } label: {
                        if session.isBusy && !session.phase.isCapturing {
                            ProgressView()
                        } else {
                            Label(
                                session.phase.isCapturing ? "Stop" : "Listen",
                                systemImage: session.phase.isCapturing ? "stop.circle.fill" : "mic.circle.fill"
                            )
                        }
                    }
                    .disabled(session.isBusy && !session.phase.isCapturing)
                    .tint(session.phase.isCapturing ? .red : .accentColor)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(session)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showSuperGrok) {
                SuperGrokSignInView {
                    session.refreshGrokAuth()
                    showSuperGrok = false
                }
            }
            .fullScreenCover(isPresented: $session.showCaptionBoard) {
                if let turn = session.captionTurn {
                    CaptionBoardView(turn: turn) {
                        session.dismissCaption()
                    }
                }
            }
            .onAppear { session.onAppear() }
        }
    }

    private var statusSection: some View {
        Section {
            Button {
                if session.gate == .connectGrok { showSuperGrok = true }
            } label: {
                LabeledContent {
                    Text(session.statusTitle)
                        .foregroundStyle(session.statusTint)
                        .fontWeight(.semibold)
                } label: {
                    Label("Status", systemImage: session.statusSymbol)
                }
            }
            .buttonStyle(.plain)
            .disabled(session.gate != .connectGrok)

            if let errorMessage = session.phase.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if !session.whoLabel.isEmpty, session.isLiveTurn {
                LabeledContent("Who") {
                    Text(session.whoLabel)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("AirPods") {
                Text(session.headphonesWorn ? "In" : "Out")
                    .foregroundStyle(session.headphonesWorn ? Color.secondary : Color.orange)
            }
        } header: {
            Text("Session")
        } footer: {
            Text(footerCopy)
        }
    }

    private var footerCopy: String {
        switch session.gate {
        case .connectGrok:
            return "Sign in with SuperGrok first. Listen still runs a demo."
        case .ready:
            switch session.phase {
            case .listening, .hearingThem:
                return session.headphonesWorn
                    ? "Point the phone at them. Pause and it lands in your ear."
                    : "Point the phone at them. No AirPods, so the translation plays on speaker."
            case .hearingMe:
                return "Talk. Pause, then they hear it and see the text."
            case .playingEar:
                return session.headphonesWorn
                    ? "Translation is in your AirPods."
                    : "No AirPods. Playing on the speaker."
            case .playingSpeaker:
                return "Hold the screen toward them."
            default:
                return session.headphonesWorn
                    ? "Listen. I guess who spoke from the language."
                    : "AirPods out. Your side plays on the speaker."
            }
        }
    }

    private var languagesSection: some View {
        Section {
            Picker("They speak", selection: Binding(
                get: { session.settings.theirLanguage },
                set: { session.settings.theirLanguage = $0; session.saveSettings() }
            )) {
                ForEach(SpokenLanguage.catalog) { item in
                    Text(item.name).tag(item.id)
                }
            }

            Picker("I hear", selection: Binding(
                get: { session.settings.myLanguage },
                set: { session.settings.myLanguage = $0; session.saveSettings() }
            )) {
                ForEach(SpokenLanguage.catalog) { item in
                    Text(item.name).tag(item.id)
                }
            }

            Button {
                session.swapLanguages()
            } label: {
                Label("Swap", systemImage: "arrow.up.arrow.down")
            }
            .disabled(session.phase.isCapturing || session.isBusy)
        } header: {
            Text("Languages")
        }
    }

    @ViewBuilder
    private var nowSection: some View {
        if !session.liveTranslation.isEmpty || !session.liveTranscript.isEmpty {
            Section {
                if !session.liveTranslation.isEmpty {
                    Text(session.liveTranslation)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !session.liveTranscript.isEmpty {
                    Text(session.liveTranscript)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text(session.whoLabel.isEmpty ? "Now" : session.whoLabel)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !session.history.isEmpty {
            Section {
                ForEach(session.history.prefix(5)) { turn in
                    Button {
                        if turn.direction == .meToThem {
                            session.captionTurn = turn
                            session.showCaptionBoard = true
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(turn.translatedText)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                            Text(turn.sourceText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Recent")
            } footer: {
                Text("Tap a line you said to show it big again.")
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(SessionController())
}
