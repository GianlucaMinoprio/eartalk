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
    var isConversationLive: Bool { keepListening }
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
        if showCaptionBoard || keepListening { return true }
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
        keepListening = true
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
        showCaptionBoard = false
        captionHolds = false
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
        listenTask?.cancel()
        liveTranscript = ""
        lastDetectedLanguage = nil
        if listenMode == .auto {
            classifiedDirection = nil
            if !showCaptionBoard {
                whoLabel = ""
            }
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
                if !capture.isRecording {
                    let mic: CaptureMic
                    switch listenMode {
                    case .auto, .locked(.themToMe):
                        mic = .them
                    case .locked(.meToThem):
                        mic = .me
                    }
                    try capture.start(mic: mic)
                }
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
        var speechFor: TimeInterval = 0
        var silentFor: TimeInterval = 0
        var started = Date()

        while !Task.isCancelled, keepListening {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if case .error = phase { break }

            capture.updateMeters()
            refreshHeadphones()

            let playing = player.isPlaying
            let bargeThreshold: Float = (playing && !headphonesWorn) ? -16 : -32
            let loudEnough = capture.averagePower > bargeThreshold

            if playing {
                if loudEnough {
                    speechFor += 0.1
                    if speechFor >= 0.35 {
                        player.stop()
                    }
                } else {
                    speechFor = 0
                }
                continue
            }

            if loudEnough {
                heardSpeech = true
                speechFor += 0.1
                silentFor = 0
            } else if heardSpeech {
                silentFor += 0.1
            }

            let elapsed = Date().timeIntervalSince(started)
            if heardSpeech, speechFor >= 0.6, silentFor >= 1.7, elapsed >= 2.2 {
                let file = (try? capture.rotate()) ?? capture.stop()
                if !capture.isRecording {
                    let mic: CaptureMic = {
                        switch listenMode {
                        case .auto, .locked(.themToMe): return .them
                        case .locked(.meToThem): return .me
                        }
                    }()
                    try? capture.start(mic: mic)
                }
                heardSpeech = false
                speechFor = 0
                silentFor = 0
                started = Date()
                liveTranscript = ""
                if listenMode == .auto {
                    classifiedDirection = nil
                }
                pipelineTask?.cancel()
                pipelineTask = Task { await finishTurn(lastChunk: file) }
            }
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

    private func finishTurn(lastChunk: URL? = nil) async {
        defer {
            if let lastChunk {
                try? FileManager.default.removeItem(at: lastChunk)
            }
        }

        do {
            let bearer = try await SuperGrokAuth.shared.validAccessToken()
            if let lastChunk {
                let bytes = (try? FileManager.default.attributesOfItem(atPath: lastChunk.path)[.size] as? NSNumber)?.intValue ?? 0
                if bytes < 2500 {
                    applyListeningPhase()
                    return
                }
                let result = try await transcribeUtterance(fileURL: lastChunk, bearer: bearer)
                appendLive(result.text)
                applyClassification(text: liveTranscript, detected: result.language)
            }

            let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard TranscriptMerge.isUsable(text) else {
                applyListeningPhase()
                return
            }

            if classifiedDirection == nil {
                applyClassification(text: text, detected: lastDetectedLanguage)
            }
            let direction = classifiedDirection ?? .themToMe
            lastAutoWasThem = direction == .themToMe

            phase = direction == .themToMe ? .translatingThem : .translatingMe

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

            presentCaption(turn, hold: true)

            let audio = try await client.synthesize(
                text: translated,
                bearer: bearer,
                voiceID: direction == .themToMe ? settings.earVoiceID : settings.speakerVoiceID,
                language: to.ttsCode
            )
            try Task.checkCancellation()
            refreshHeadphones()
            let route: AudioRoute
            if direction == .themToMe {
                phase = .playingEar
                route = headphonesWorn ? .earbuds : .speaker
            } else {
                phase = .playingSpeaker
                route = .speaker
            }
            let volume = direction == .themToMe ? Float(settings.earVolume) : Float(settings.speakerVolume)
            try await player.play(data: audio, route: route, volume: volume)
            applyListeningPhase()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
            applyListeningPhase()
        } catch {
            guard !Task.isCancelled else { return }
            phase = .error(error.localizedDescription)
        }
    }


    private func transcribeUtterance(fileURL: URL, bearer: String) async throws -> STTResult {
        var lastError: Error?
        var best: STTResult?

        func consider(_ result: STTResult) {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard TranscriptMerge.isUsable(text) else { return }
            guard let current = best else {
                best = result
                return
            }
            if text.count > current.text.count {
                best = result
            }
        }

        let hints: [String?]
        switch listenMode {
        case .auto:
            hints = [nil, settings.theirLang.sttCode, settings.myLang.sttCode]
        case .locked(.themToMe):
            hints = [settings.theirLang.sttCode, nil]
        case .locked(.meToThem):
            hints = [settings.myLang.sttCode, nil]
        }

        for hint in hints {
            do {
                let result = try await client.transcribe(fileURL: fileURL, bearer: bearer, language: hint)
                consider(result)
                if let best, best.text.count >= 8 { return best }
            } catch {
                lastError = error
            }
        }

        if let best { return best }
        if let lastError { throw lastError }
        throw XAIClientError.emptyTranscript
    }

    private func appendLive(_ piece: String) {
        liveTranscript = TranscriptMerge.append(existing: liveTranscript, incoming: piece)
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
            presentCaption(turn, hold: true)
            phase = .playingEar
            debugLine = ""
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            phase = .listening
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
            phase = .listening
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
