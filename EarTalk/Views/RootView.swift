import SwiftUI

/// Main screen: pick languages, hear them in your ear, speak back with big text.
struct RootView: View {
    @EnvironmentObject private var session: SessionController
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                languagesSection
                actionsSection
                statusSection
                nowSection
                historySection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("EarTalk")
            .navigationBarTitleDisplayMode(.large)
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

                    Button {
                        session.startHearingThem()
                    } label: {
                        if session.phase == .hearingThem {
                            Label("Hearing…", systemImage: "ear.fill")
                        } else {
                            Label("Hear them", systemImage: "ear")
                        }
                    }
                    .disabled(session.isBusy && session.phase != .hearingThem)
                    .tint(session.phase == .hearingThem ? .red : .accentColor)

                    Button {
                        session.startHearingMe()
                    } label: {
                        if session.phase == .hearingMe {
                            Label("Listening…", systemImage: "mic.fill")
                        } else {
                            Label("I speak", systemImage: "mic.circle.fill")
                        }
                    }
                    .disabled(session.isBusy && session.phase != .hearingMe)
                    .buttonStyle(.borderedProminent)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environmentObject(session)
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $session.showCaptionBoard) {
                if let turn = session.captionTurn {
                    CaptionBoardView(turn: turn) {
                        session.dismissCaption()
                    }
                }
            }
        }
    }

    // MARK: - Sections

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
                Label("Swap languages", systemImage: "arrow.up.arrow.down")
            }
            .disabled(session.phase.isCapturing || session.isBusy)
        } header: {
            Text("Languages")
        } footer: {
            Text("They speak Chinese, you hear English. Then I speak flips it the other way.")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                session.startHearingThem()
            } label: {
                Label(
                    session.phase == .hearingThem ? "Hearing them…" : "Hear them",
                    systemImage: session.phase == .hearingThem ? "ear.fill" : "ear"
                )
            }
            .disabled(session.isBusy && session.phase != .hearingThem)
            .foregroundStyle(session.phase == .hearingThem ? Color.red : Color.accentColor)

            Button {
                session.startHearingMe()
            } label: {
                Label(
                    session.phase == .hearingMe ? "Listening to you…" : "I speak",
                    systemImage: session.phase == .hearingMe ? "mic.fill" : "mic.circle.fill"
                )
            }
            .disabled(session.isBusy && session.phase != .hearingMe)
            .fontWeight(.semibold)

            if session.showsStop {
                Button("Stop", role: .destructive) {
                    session.stopSession()
                }
            }
        } header: {
            Text("Talk")
        } footer: {
            Text("Hear them puts the translation in your AirPods. I speak plays their language out loud and shows huge text.")
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent {
                Text(session.phase.shortLabel)
                    .foregroundStyle(session.phase.tint)
                    .fontWeight(.semibold)
            } label: {
                Label("Status", systemImage: session.phase.symbolName)
            }

            if let errorMessage = session.phase.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if !session.debugLine.isEmpty {
                Text(session.debugLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !SuperGrokSession.isSignedIn {
                Label("Demo mode. Sign in with SuperGrok in Settings.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Session")
        } footer: {
            Text(footerCopy)
        }
    }

    private var footerCopy: String {
        switch session.phase {
        case .hearingThem:
            return "Point the phone at them. Pause and it lands in your ear."
        case .hearingMe:
            return "Talk. When you pause, they hear it and see the big text."
        case .playingSpeaker:
            return "Hold the screen toward them."
        default:
            return "Hear them for your AirPods. I speak for the person in front."
        }
    }

    private var nowSection: some View {
        Section {
            if session.liveTranscript.isEmpty && session.liveTranslation.isEmpty {
                ContentUnavailableView(
                    "Nothing yet",
                    systemImage: "globe",
                    description: Text("Tap Hear them when they talk, or I speak when it is your turn.")
                )
                .listRowBackground(Color.clear)
            } else {
                if !session.liveTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Heard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(session.liveTranscript)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
                if !session.liveTranslation.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Translation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(session.liveTranslation)
                            .font(.title3.weight(.semibold))
                            .textSelection(.enabled)
                    }
                }
            }
        } header: {
            Text("Now")
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !session.history.isEmpty {
            Section {
                ForEach(session.history.prefix(8)) { turn in
                    Button {
                        if turn.direction == .meToThem {
                            session.captionTurn = turn
                            session.showCaptionBoard = true
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(
                                turn.direction == .themToMe ? "Them → you" : "You → them",
                                systemImage: turn.direction == .themToMe ? "ear" : "person.wave.2"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text(turn.sourceText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                            Text(turn.translatedText)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(4)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Recent")
            } footer: {
                Text("Tap a line you said to show the big text again.")
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(SessionController())
}
