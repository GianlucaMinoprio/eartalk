import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss

    @State private var earVoiceID: String = AppSettings.defaultEarVoice
    @State private var speakerVoiceID: String = AppSettings.defaultSpeakerVoice
    @State private var myLanguage: String = AppSettings.defaultMyLanguage
    @State private var theirLanguage: String = AppSettings.defaultTheirLanguage
    @State private var earVolume: Double = AppSettings.defaultEarVolume
    @State private var speakerVolume: Double = AppSettings.defaultSpeakerVolume
    @State private var showSuperGrok = false
    @State private var signedIn = SuperGrokSession.isSignedIn
    @State private var accountHint = SuperGrokSession.load()?.accountHint
    @State private var previewing: String?
    @State private var previewError: String?

    private let voiceChoices = ["eve", "ara", "rex", "sal", "leo", "ursa"]
    private let client = XAIClient()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if signedIn {
                        LabeledContent("Status") {
                            Text("Signed in")
                                .foregroundStyle(.green)
                                .fontWeight(.semibold)
                        }
                        if let accountHint {
                            LabeledContent("Account") {
                                Text(accountHint)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Button("Sign out", role: .destructive) {
                            Task {
                                await SuperGrokAuth.shared.signOut()
                                refreshAuth()
                            }
                        }
                    } else {
                        Button {
                            showSuperGrok = true
                        } label: {
                            Label("Sign in with SuperGrok", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    }
                } header: {
                    Text("SuperGrok")
                } footer: {
                    Text("Uses your grok.com or X Premium+ subscription. Tokens stay in the Keychain on this phone.")
                }

                Section {
                    Picker("They speak", selection: $theirLanguage) {
                        ForEach(SpokenLanguage.catalog) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                    Picker("I speak", selection: $myLanguage) {
                        ForEach(SpokenLanguage.catalog) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                } header: {
                    Text("Languages")
                }

                Section {
                    voiceRows(selection: $earVoiceID, route: .earbuds)
                    if let previewError {
                        Text(previewError)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Ear voice")
                } footer: {
                    Text(signedIn
                         ? (Headphones.areWorn()
                            ? "Tap play to hear a sample in your earbuds."
                            : "No earbuds connected. Preview plays on the speaker.")
                         : "Sign in to preview voices.")
                }

                Section {
                    voiceRows(selection: $speakerVoiceID, route: .speaker)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speaker \(Int(speakerVolume * 100))%")
                        Slider(value: $speakerVolume, in: 0.2...1, step: 0.05)
                    }
                } header: {
                    Text("Speaker")
                } footer: {
                    Text("This is what they hear when you talk.")
                }

                Section {
                    LabeledContent("Listen") {
                        Text("Their language in your ear. Yours out loud.")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Caption") {
                        Text("Big text every turn")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("App") {
                        Text("EarTalk 1.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear(perform: load)
            .onDisappear { session.player.stop() }
            .sheet(isPresented: $showSuperGrok, onDismiss: refreshAuth) {
                SuperGrokSignInView {
                    refreshAuth()
                }
            }
        }
    }

    @ViewBuilder
    private func voiceRows(selection: Binding<String>, route: AudioRoute) -> some View {
        ForEach(voiceChoices, id: \.self) { voice in
            HStack {
                Button {
                    selection.wrappedValue = voice
                } label: {
                    Label(voice.capitalized, systemImage: selection.wrappedValue == voice ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.wrappedValue == voice ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
                Spacer()
                Button {
                    preview(voice, route: route, language: route == .earbuds ? myLanguage : theirLanguage)
                } label: {
                    if previewing == "\(routeLabel(route))-\(voice)" {
                        ProgressView()
                    } else {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                    }
                }
                .disabled(!signedIn || previewing != nil)
                .accessibilityLabel("Preview \(voice)")
            }
        }
    }

    private func routeLabel(_ route: AudioRoute) -> String {
        switch route {
        case .earbuds: return "ear"
        case .speaker: return "speak"
        }
    }

    private func load() {
        earVoiceID = session.settings.earVoiceID
        speakerVoiceID = session.settings.speakerVoiceID
        myLanguage = session.settings.myLanguage
        theirLanguage = session.settings.theirLanguage
        earVolume = session.settings.earVolume
        speakerVolume = session.settings.speakerVolume
        refreshAuth()
    }

    private func refreshAuth() {
        signedIn = SuperGrokSession.isSignedIn
        accountHint = SuperGrokSession.load()?.accountHint
        session.refreshGrokAuth()
    }

    private func save() {
        session.settings.chatModel = AppSettings.defaultChatModel
        session.settings.earVoiceID = nonempty(earVoiceID, default: AppSettings.defaultEarVoice)
        session.settings.speakerVoiceID = nonempty(speakerVoiceID, default: AppSettings.defaultSpeakerVoice)
        session.settings.myLanguage = nonempty(myLanguage, default: AppSettings.defaultMyLanguage)
        session.settings.theirLanguage = nonempty(theirLanguage, default: AppSettings.defaultTheirLanguage)
        session.settings.earVolume = earVolume
        session.settings.speakerVolume = speakerVolume
        session.saveSettings()
        dismiss()
    }

    private func preview(_ voice: String, route: AudioRoute, language: String) {
        previewError = nil
        previewing = "\(routeLabel(route))-\(voice)"
        Task {
            defer { previewing = nil }
            do {
                let bearer = try await SuperGrokAuth.shared.validAccessToken()
                let line = route == .earbuds
                    ? "This is what you will hear in your ear."
                    : "This is what they will hear out loud."
                let audio = try await client.synthesize(
                    text: line,
                    bearer: bearer,
                    voiceID: voice,
                    language: nonempty(language, default: AppSettings.defaultMyLanguage)
                )
                let volume = route == .earbuds ? Float(earVolume) : Float(speakerVolume)
                try await session.player.play(data: audio, route: route, volume: volume)
            } catch {
                previewError = error.localizedDescription
            }
        }
    }

    private func nonempty(_ value: String, default defaultValue: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    }
}

#Preview {
    SettingsView()
        .environmentObject(SessionController())
}
