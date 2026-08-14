import Foundation
import SwiftUI
import UIKit
import AVFoundation

@MainActor
final class SessionController: ObservableObject {
    @Published var phase: SessionPhase = .idle
    @Published var liveTranscript: String = ""
    @Published var liveTranslation: String = ""
    @Published var history: [ConversationTurn] = []
    @Published var settings: AppSettings
    @Published var debugLine: String = ""
    @Published var showCaptionBoard = false
    @Published var captionTurn: ConversationTurn?
    @Published var whoLabel: String = ""
    @Published var grokSignedIn = SuperGrokSession.isSignedIn
    @Published var headphonesWorn = Headphones.areWorn()
    @Published var captionHolds = false

    let capture = AudioCaptureService()
    let player = SpeechPlayer()
    private let client = XAIClient()

    private var pipelineTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var keepListening = false
    private var didHandleLaunchArgs = false
    private var listenMode: ListenMode = .auto
    private var classifiedDirection: TalkDirection?
    private var lastDetectedLanguage: String?
    private var lastAutoWasThem = true
    private var routeObserver: NSObjectProtocol?

    private enum ListenMode: Equatable {
        case auto
        case locked(TalkDirection)
    }

    init() {
        settings = AppSettings.load()
    }

    enum Gate: Equatable {
        case connectGrok
        case ready
    }

    var gate: Gate {
        grokSignedIn ? .ready : .connectGrok
    }

    var statusTitle: String {
        switch gate {
        case .connectGrok:
            return "Connect Grok"
        case .ready:
            return phase == .idle ? "Ready" : phase.shortLabel
        }
    }

    var statusSymbol: String {
        switch gate {
        case .connectGrok: return "person.crop.circle.badge.plus"
        case .ready: return phase.symbolName
        }
    }

    var statusTint: Color {
        switch gate {
        case .connectGrok: return .accentColor
        case .ready: return phase == .idle ? .green : phase.tint
        }
    }

    var isBusy: Bool { phase.isBusy }
    var isSimulator: Bool { DeviceEnvironment.isSimulator }

    var showsStop: Bool {
        switch phase {
        case .idle:
            return false
        default:
            return true
        }
    }

    var isLiveTurn: Bool {
        switch phase {
        case .idle, .error:
            return false
        default:
            return true
        }
    }

    func onAppear() {
        refreshGrokAuth()
        refreshHeadphones()
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshHeadphones()
            }
        }
    }

    func refreshHeadphones() {
        headphonesWorn = Headphones.areWorn()
    }

    func refreshGrokAuth() {
        grokSignedIn = SuperGrokSession.isSignedIn
    }

    func saveSettings() {
        settings.save()
    }

    func swapLanguages() {
        let mine = settings.myLanguage
        settings.myLanguage = settings.theirLanguage
        settings.theirLanguage = mine
        settings.save()
    }

    func startListening() {
        keepListening = true
        listenMode = .auto
        classifiedDirection = nil
        beginCapture()
    }

    func startHearingThem() {
        keepListening = true
        listenMode = .locked(.themToMe)
        classifiedDirection = .themToMe
        whoLabel = "They speak"
        beginCapture()
    }

    func startHearingMe() {
        keepListening = false
        listenMode = .locked(.meToThem)
        classifiedDirection = .meToThem
        whoLabel = "I speak"
        beginCapture()
    }

    func stopSession() {
        keepListening = false
        listenTask?.cancel()
        pipelineTask?.cancel()
        _ = capture.stop()
        player.stop()
        phase = .idle
        debugLine = ""
        liveTranscript = ""
        liveTranslation = ""
        whoLabel = ""
        captionHolds = false
        showCaptionBoard = false
    }

    func resetToIdle() {
        stopSession()
        showCaptionBoard = false
        captionTurn = nil
        debugLine = ""
    }

    func presentCaption(_ turn: ConversationTurn, hold: Bool) {
        captionTurn = turn
        captionHolds = hold
        showCaptionBoard = true
    }

    func dismissCaption() {
        let shouldResume = keepListening && captionHolds
        showCaptionBoard = false
        captionHolds = false
        if shouldResume, !phase.isCapturing {
            beginCapture()
        }
    }

    /// Headless drive: `xcrun simctl launch <udid> com.gianlucaminoprio.eartalk speak`
    func handleLaunchArguments(_ args: [String]) {
        guard !didHandleLaunchArgs else { return }
        didHandleLaunchArgs = true
        for arg in args {
            if arg.hasPrefix("their=") {
                settings.theirLanguage = String(arg.dropFirst(6))
                settings.save()
            } else if arg.hasPrefix("mine=") {
                settings.myLanguage = String(arg.dropFirst(5))
                settings.save()
            }
        }
        if args.contains("speak") {
            startHearingMe()
        } else if args.contains("hear") {
            startHearingThem()
        } else if args.contains("listen") {
            startListening()
        } else if args.contains("reset") {
            resetToIdle()
        }
    }

    /// Simulator / `simctl openurl` hooks: eartalk://hear|speak|stop|reset
    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "eartalk" else { return }
        let action = (url.host ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        switch action {
        case "hear", "them":
            startHearingThem()
        case "listen", "auto":
            startListening()
        case "speak", "me":
            startHearingMe()
        case "stop":
            stopSession()
        case "reset":
            resetToIdle()
        case "caption":
            if let last = history.first(where: { $0.direction == .meToThem }) {
                captionTurn = last
                showCaptionBoard = true
            }
        default:
            debugLine = "Unknown URL \(url.absoluteString)"
        }
    }

    // MARK: - Capture

    private func beginCapture() {
        refreshHeadphones()
        pipelineTask?.cancel()
        listenTask?.cancel()
        player.stop()
        liveTranscript = ""
        liveTranslation = ""
        lastDetectedLanguage = nil
        showCaptionBoard = false
        captionHolds = false
        if listenMode == .auto {
            classifiedDirection = nil
            whoLabel = ""
        }
        debugLine = ""

        if !settings.hasLiveCredential {
            pipelineTask = Task { await runDemo() }
            return
        }

        pipelineTask = Task {
            let ok = await capture.requestPermission()
            guard !Task.isCancelled else { return }
            guard ok else {
                phase = .error("Microphone permission denied")
                return
            }
            do {
                let mic: CaptureMic
                switch listenMode {
                case .auto, .locked(.themToMe):
                    mic = .them
                case .locked(.meToThem):
                    mic = .me
                }
                try capture.start(mic: mic)
                applyListeningPhase()
                debugLine = listenHint
                startListenMonitor()
            } catch {
                guard !Task.isCancelled else { return }
                phase = .error(error.localizedDescription)
            }
        }
    }

    private var listenHint: String {
        switch listenMode {
        case .auto:
            return "Talk or let them talk. I guess from the language."
        case .locked(.themToMe):
            return "Point the phone at them. Silence ends the turn."
        case .locked(.meToThem):
            return "Talk. Silence translates you out."
        }
    }

    private func applyListeningPhase() {
        switch classifiedDirection {
        case .themToMe:
            phase = .hearingThem
        case .meToThem:
            phase = .hearingMe
        case nil:
            phase = listenMode == .auto ? .listening : .hearingThem
        }
    }

    private func startListenMonitor() {
        listenTask?.cancel()
        listenTask = Task { await monitorListening() }
    }

    private func isInListenPhase(_ phase: SessionPhase) -> Bool {
        switch phase {
        case .listening, .hearingThem, .hearingMe:
            return true
        default:
            return false
        }
    }

    private func monitorListening() async {
        var heardSpeech = false
        var silentFor: TimeInterval = 0
        var lastRotate = Date()
        let started = Date()

        while !Task.isCancelled, isInListenPhase(phase) {
            try? await Task.sleep(nanoseconds: 100_000_000)

            capture.updateMeters()
            if capture.averagePower > -28 {
                heardSpeech = true
                silentFor = 0
            } else if heardSpeech {
                silentFor += 0.1
            }

            if Date().timeIntervalSince(lastRotate) >= 2.6, isInListenPhase(phase) {
                lastRotate = Date()
                await liveTranscribeChunk()
            }

            let elapsed = Date().timeIntervalSince(started)
            if heardSpeech, silentFor >= 1.5, elapsed >= 1.8 {
                let lastChunk = capture.stop()
                pipelineTask = Task { await finishTurn(lastChunk: lastChunk) }
                return
            }
        }
    }

    private func sttLanguageHint() -> String? {
        switch listenMode {
        case .auto:
            return nil
        case .locked(.themToMe):
            return settings.theirLang.sttCode
        case .locked(.meToThem):
            return settings.myLang.sttCode
        }
    }

    private func applyClassification(text: String, detected: String?) {
        lastDetectedLanguage = detected
        switch listenMode {
        case .locked(let direction):
            classifiedDirection = direction
        case .auto:
            let result = SpeakerSense.direction(
                text: text,
                detectedLanguage: detected,
                my: settings.myLang,
                their: settings.theirLang
            )
            classifiedDirection = result.0
            whoLabel = result.0 == .themToMe ? "They speak" : "I speak"
            applyListeningPhase()
        }
    }

    private func liveTranscribeChunk() async {
        guard settings.hasLiveCredential else { return }
        do {
            guard let url = try capture.rotate() else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            try Task.checkCancellation()
            let bearer = try await SuperGrokAuth.shared.validAccessToken()
            let result = try await client.transcribe(
                fileURL: url,
                bearer: bearer,
                language: sttLanguageHint()
            )
            appendLive(result.text)
            if classifiedDirection == nil || listenMode == .auto {
                applyClassification(text: liveTranscript, detected: result.language)
            }
        } catch {
            // Chunk STT can fail on silence. Keep listening.
        }
    }

    private func finishTurn(lastChunk: URL? = nil) async {
        // Never run this on listenTask. Canceling that task from here used to
        // mark the translate/TTS work cancelled, then we swallowed it and
        // stayed on Translating.
        listenTask?.cancel()
        listenTask = nil
        defer {
            if let lastChunk {
                try? FileManager.default.removeItem(at: lastChunk)
            }
        }

        do {
            let bearer = try await SuperGrokAuth.shared.validAccessToken()
            if let lastChunk {
                if let result = try? await client.transcribe(
                    fileURL: lastChunk,
                    bearer: bearer,
                    language: sttLanguageHint()
                ) {
                    appendLive(result.text)
                    applyClassification(text: liveTranscript, detected: result.language)
                }
            }

            let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                phase = .error("Nothing heard. Try again a bit closer.")
                return
            }

            if classifiedDirection == nil {
                applyClassification(text: text, detected: lastDetectedLanguage)
            }
            let direction = classifiedDirection ?? .themToMe
            lastAutoWasThem = direction == .themToMe

            phase = direction == .themToMe ? .translatingThem : .translatingMe
            debugLine = "Translate \(settings.chatModel)…"

            let from = direction == .themToMe ? settings.theirLang : settings.myLang
            let to = direction == .themToMe ? settings.myLang : settings.theirLang
            let translated = try await client.translate(
                text: text,
                from: from,
                to: to,
                bearer: bearer,
                model: "grok-4-1-fast-non-reasoning"
            )
            try Task.checkCancellation()
            liveTranslation = translated

            let turn = ConversationTurn(
                direction: direction,
                sourceText: text,
                translatedText: translated,
                sourceLanguage: from.id,
                targetLanguage: to.id
            )
            history.insert(turn, at: 0)
            if history.count > 30 { history = Array(history.prefix(30)) }

            if direction == .themToMe {
                presentCaption(turn, hold: false)
                phase = .playingEar
                debugLine = ""
                let audio = try await client.synthesize(
                    text: translated,
                    bearer: bearer,
                    voiceID: settings.earVoiceID,
                    language: to.ttsCode
                )
                try Task.checkCancellation()
                refreshHeadphones()
                let inbound: AudioRoute = headphonesWorn ? .earbuds : .speaker
                try await player.play(data: audio, route: inbound, volume: Float(settings.earVolume))
                try Task.checkCancellation()
                showCaptionBoard = false
                if keepListening {
                    beginCapture()
                } else {
                    phase = .idle
                    debugLine = ""
                }
            } else {
                presentCaption(turn, hold: true)
                phase = .playingSpeaker
                debugLine = ""
                let audio = try await client.synthesize(
                    text: translated,
                    bearer: bearer,
                    voiceID: settings.speakerVoiceID,
                    language: to.ttsCode
                )
                try Task.checkCancellation()
                try await player.play(data: audio, route: .speaker, volume: Float(settings.speakerVolume))
                try Task.checkCancellation()
                phase = .idle
                debugLine = ""
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
            if phase == .translatingThem || phase == .translatingMe || phase == .playingEar || phase == .playingSpeaker {
                phase = .error("Stopped.")
            }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .error(error.localizedDescription)
            debugLine = ""
        }
    }

    private func appendLive(_ piece: String) {
        let piece = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        guard piece.count > 2 else { return }
        if liveTranscript.isEmpty {
            liveTranscript = piece
            return
        }
        if liveTranscript.localizedCaseInsensitiveContains(piece) { return }
        if piece.localizedCaseInsensitiveContains(liveTranscript) {
            liveTranscript = piece
            return
        }
        liveTranscript = stitchTranscript(existing: liveTranscript, incoming: piece)
    }

    private func stitchTranscript(existing: String, incoming: String) -> String {
        let existingWords = existing.split(separator: " ").map(String.init)
        let incomingWords = incoming.split(separator: " ").map(String.init)
        guard !existingWords.isEmpty, !incomingWords.isEmpty else {
            return (existing + " " + incoming).trimmingCharacters(in: .whitespaces)
        }
        let maxOverlap = min(6, existingWords.count, incomingWords.count)
        if maxOverlap > 0 {
            for n in stride(from: maxOverlap, through: 1, by: -1) {
                let tail = existingWords.suffix(n).map { $0.lowercased() }
                let head = incomingWords.prefix(n).map { $0.lowercased() }
                if tail == head {
                    return (existingWords + incomingWords.dropFirst(n)).joined(separator: " ")
                }
            }
        }
        return existing + " " + incoming
    }

    // MARK: - Demo

    private func runDemo() async {
        let direction: TalkDirection
        switch listenMode {
        case .locked(let locked):
            direction = locked
        case .auto:
            direction = lastAutoWasThem ? .themToMe : .meToThem
            lastAutoWasThem.toggle()
        }
        classifiedDirection = direction

        if direction == .themToMe {
            phase = .hearingThem
            whoLabel = "They speak"
            debugLine = ""
            liveTranscript = DemoLines.themSaid(settings.theirLang)
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            phase = .translatingThem
            liveTranslation = DemoLines.themHeard(settings.myLang)
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let turn = ConversationTurn(
                direction: .themToMe,
                sourceText: liveTranscript,
                translatedText: liveTranslation,
                sourceLanguage: settings.theirLanguage,
                targetLanguage: settings.myLanguage
            )
            history.insert(turn, at: 0)
            presentCaption(turn, hold: false)
            phase = .playingEar
            debugLine = ""
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            showCaptionBoard = false
            phase = .idle
        } else {
            phase = .hearingMe
            whoLabel = "I speak"
            debugLine = ""
            liveTranscript = DemoLines.meSaid(settings.myLang)
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            phase = .translatingMe
            liveTranslation = DemoLines.meOut(settings.theirLang)
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let turn = ConversationTurn(
                direction: .meToThem,
                sourceText: liveTranscript,
                translatedText: liveTranslation,
                sourceLanguage: settings.myLanguage,
                targetLanguage: settings.theirLanguage
            )
            history.insert(turn, at: 0)
            presentCaption(turn, hold: true)
            phase = .playingSpeaker
            debugLine = ""
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            phase = .idle
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
