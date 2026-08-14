import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss

    @State private var chatModel: String = AppSettings.defaultChatModel
    @State private var earVoiceID: String = AppSettings.defaultEarVoice
    @State private var speakerVoiceID: String = AppSettings.defaultSpeakerVoice
    @State private var myLanguage: String = AppSettings.defaultMyLanguage
    @State private var theirLanguage: String = AppSettings.defaultTheirLanguage
    @State private var earVolume: Double = AppSettings.defaultEarVolume
    @State private var speakerVolume: Double = AppSettings.defaultSpeakerVolume
    @State private var showSuperGrok = false
    @State private var signedIn = SuperGrokSession.isSignedIn
    @State private var accountHint = SuperGrokSession.load()?.accountHint

    private let modelChoices = [
        "grok-4.5",
        "grok-4-1-fast-non-reasoning",
        "grok-4.6"
    ]

    private let voiceChoices = ["eve", "ara", "rex", "sal", "leo", "ursa"]

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
                    Picker("I hear / I speak", selection: $myLanguage) {
                        ForEach(SpokenLanguage.catalog) { item in
                            Text(item.name).tag(item.id)
                        }
                    }
                } header: {
                    Text("Languages")
                } footer: {
                    Text("Pre-select what you expect them to speak, and the language you want in your ear.")
                }

                Section {
                    Picker("Chat", selection: $chatModel) {
                        ForEach(modelChoices, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    if !modelChoices.contains(chatModel) {
                        TextField("Custom model id", text: $chatModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    }

                    Picker("Voice in my ear", selection: $earVoiceID) {
                        ForEach(voiceChoices, id: \.self) { voice in
                            Text(voice).tag(voice)
                        }
                    }
                    Picker("Voice out loud", selection: $speakerVoiceID) {
                        ForEach(voiceChoices, id: \.self) { voice in
                            Text(voice).tag(voice)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ear volume \(Int(earVolume * 100))%")
                        Slider(value: $earVolume, in: 0.2...1, step: 0.05)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Speaker \(Int(speakerVolume * 100))%")
                        Slider(value: $speakerVolume, in: 0.2...1, step: 0.05)
                    }
                } header: {
                    Text("Model")
                } footer: {
                    Text("Eve in your AirPods. Speaker plays their language so they can hear you too.")
                }

                Section {
                    LabeledContent("Hear them") {
                        Text("Phone mic, translation in AirPods")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("I speak") {
                        Text("Your words out loud + big text")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Silence") {
                        Text("Ends the turn")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("How it works")
                } footer: {
                    Text("Point the phone at them when they talk so the built-in mic hears them, not your AirPods.")
                }

                Section {
                    LabeledContent("App") {
                        Text("EarTalk 1.0")
                            .foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://docs.x.ai/developers/model-capabilities/audio/voice")!) {
                        Label("xAI voice docs", systemImage: "link")
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
            .sheet(isPresented: $showSuperGrok, onDismiss: refreshAuth) {
                SuperGrokSignInView {
                    refreshAuth()
                }
            }
        }
    }

    private func load() {
        chatModel = session.settings.chatModel
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
    }

    private func save() {
        session.settings.chatModel = nonempty(chatModel, default: AppSettings.defaultChatModel)
        session.settings.earVoiceID = nonempty(earVoiceID, default: AppSettings.defaultEarVoice)
        session.settings.speakerVoiceID = nonempty(speakerVoiceID, default: AppSettings.defaultSpeakerVoice)
        session.settings.myLanguage = nonempty(myLanguage, default: AppSettings.defaultMyLanguage)
        session.settings.theirLanguage = nonempty(theirLanguage, default: AppSettings.defaultTheirLanguage)
        session.settings.earVolume = earVolume
        session.settings.speakerVolume = speakerVolume
        session.saveSettings()
        dismiss()
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
