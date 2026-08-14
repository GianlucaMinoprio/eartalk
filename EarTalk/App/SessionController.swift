import Foundation
import SwiftUI
import UIKit

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

    let capture = AudioCaptureService()
    let player = SpeechPlayer()
    private let client = XAIClient()

    private var pipelineTask: Task<Void, Never>?
    private var listenTask: Task<Void, Never>?
    private var keepHearingThem = false
    private var didHandleLaunchArgs = false

    init() {
        settings = AppSettings.load()
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

    func saveSettings() {
        settings.save()
    }

    func swapLanguages() {
        let mine = settings.myLanguage
        settings.myLanguage = settings.theirLanguage
        settings.theirLanguage = mine
        settings.save()
    }

    func startHearingThem() {
        keepHearingThem = true
        beginCapture(direction: .themToMe)
    }

    func startHearingMe() {
        keepHearingThem = false
        beginCapture(direction: .meToThem)
    }

    func stopSession() {
        keepHearingThem = false
        listenTask?.cancel()
        pipelineTask?.cancel()
        _ = capture.stop()
        player.stop()
        phase = .idle
        debugLine = "Stopped"
        liveTranscript = ""
        liveTranslation = ""
    }

    func resetToIdle() {
        stopSession()
        showCaptionBoard = false
        captionTurn = nil
        debugLine = ""
    }

    func dismissCaption() {
        showCaptionBoard = false
    }

    /// Headless drive: `xcrun simctl launch <udid> com.gianlucaminoprio.eartalk speak`
    func handleLaunchArguments(_ args: [String]) {
        guard !didHandleLaunchArgs else { return }
        didHandleLaunchArgs = true
        if args.contains("speak") {
            startHearingMe()
        } else if args.contains("hear") {
            startHearingThem()
        } else if args.contains("reset") {
            resetToIdle()
        }
    }

    /// Simulator / `simctl openurl` hooks: eartalk://hear|speak|stop|reset
    func handleOpenURL(_ url: URL) {
        guard url.scheme?.lowercased() == "eartalk" else { return }
        let action = (url.host ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        switch action {
        case "hear", "listen", "them":
            startHearingThem()
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

    private func beginCapture(direction: TalkDirection) {
        pipelineTask?.cancel()
        listenTask?.cancel()
        player.stop()
        liveTranscript = ""
        liveTranslation = ""
        debugLine = ""

        if !settings.hasLiveCredential {
            pipelineTask = Task { await runDemo(direction: direction) }
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
                try capture.start(mic: direction == .themToMe ? .them : .me)
                phase = direction == .themToMe ? .hearingThem : .hearingMe
                debugLine = direction == .themToMe
                    ? "Point the phone at them. Silence ends the turn."
                    : "Talk. Silence translates you out."
                startListenMonitor(direction: direction)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .error(error.localizedDescription)
            }
        }
    }

    private func startListenMonitor(direction: TalkDirection) {
        listenTask?.cancel()
        listenTask = Task { await monitorListening(direction: direction) }
    }

    private func monitorListening(direction: TalkDirection) async {
        var heardSpeech = false
        var silentFor: TimeInterval = 0
        var lastRotate = Date()
        let started = Date()
        let listeningPhase: SessionPhase = direction == .themToMe ? .hearingThem : .hearingMe

        while !Task.isCancelled, phase == listeningPhase {
            try? await Task.sleep(nanoseconds: 100_000_000)

            capture.updateMeters()
            if capture.averagePower > -28 {
                heardSpeech = true
                silentFor = 0
            } else if heardSpeech {
                silentFor += 0.1
            }

            if Date().timeIntervalSince(lastRotate) >= 2.6, phase == listeningPhase {
                lastRotate = Date()
                await liveTranscribeChunk(direction: direction)
            }

            let elapsed = Date().timeIntervalSince(started)
            if heardSpeech, silentFor >= 1.5, elapsed >= 1.8 {
                await finishTurn(direction: direction)
                return
            }
        }
    }

    private func liveTranscribeChunk(direction: TalkDirection) async {
        guard settings.hasLiveCredential else { return }
        do {
            guard let url = try capture.rotate() else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            try Task.checkCancellation()
            let bearer = try await SuperGrokAuth.shared.validAccessToken()
            let lang = direction == .themToMe ? settings.theirLang.sttCode : settings.myLang.sttCode
            let piece = try await client.transcribe(fileURL: url, bearer: bearer, language: lang)
            appendLive(piece)
        } catch {
            // Chunk STT can fail on silence. Keep listening.
        }
    }

    private func finishTurn(direction: TalkDirection) async {
        listenTask?.cancel()
        let lastChunk = capture.stop()
        defer {
            if let lastChunk {
                try? FileManager.default.removeItem(at: lastChunk)
            }
        }

        do {
            let bearer = try await SuperGrokAuth.shared.validAccessToken()
            if let lastChunk {
                phase = direction == .themToMe ? .transcribingThem : .transcribingMe
                debugLine = "STT…"
                let lang = direction == .themToMe ? settings.theirLang.sttCode : settings.myLang.sttCode
                if let piece = try? await client.transcribe(fileURL: lastChunk, bearer: bearer, language: lang) {
                    appendLive(piece)
                }
            }

            let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                phase = .error("Nothing heard. Try again a bit closer.")
                return
            }

            phase = direction == .themToMe ? .translatingThem : .translatingMe
            debugLine = "Translate \(settings.chatModel)…"

            let from = direction == .themToMe ? settings.theirLang : settings.myLang
            let to = direction == .themToMe ? settings.myLang : settings.theirLang
            let translated = try await client.translate(
                text: text,
                from: from,
                to: to,
                bearer: bearer,
                model: settings.chatModel
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
                phase = .playingEar
                debugLine = "Eve in your ear…"
                let audio = try await client.synthesize(
                    text: translated,
                    bearer: bearer,
                    voiceID: settings.earVoiceID,
                    language: to.ttsCode
                )
                try Task.checkCancellation()
                try await player.play(data: audio, route: .earbuds, volume: Float(settings.earVolume))
                try Task.checkCancellation()
                if keepHearingThem {
                    beginCapture(direction: .themToMe)
                } else {
                    phase = .idle
                    debugLine = ""
                }
            } else {
                captionTurn = turn
                showCaptionBoard = true
                phase = .playingSpeaker
                debugLine = "Speaking out…"
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
                debugLine = "Hold the screen toward them"
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
            // ignore
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

    private func runDemo(direction: TalkDirection) async {
        if direction == .themToMe {
            phase = .hearingThem
            debugLine = "Demo. Pretending they spoke Chinese."
            liveTranscript = "你好，很高兴认识你。今天天气很好。"
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            phase = .translatingThem
            liveTranslation = "Hi, nice to meet you. The weather is really nice today."
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
            phase = .playingEar
            debugLine = "Demo ear playback skipped"
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            if keepHearingThem {
                phase = .idle
                debugLine = "Demo turn done. Tap Hear them again."
                keepHearingThem = false
            } else {
                phase = .idle
                debugLine = ""
            }
        } else {
            phase = .hearingMe
            debugLine = "Demo. Pretending you spoke English."
            liveTranscript = "Hi, nice to meet you. Want to grab coffee around the corner?"
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            phase = .translatingMe
            liveTranslation = "你好，很高兴认识你。要不要去街角喝杯咖啡？"
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
            captionTurn = turn
            showCaptionBoard = true
            phase = .playingSpeaker
            debugLine = "Demo speaker playback skipped"
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            phase = .idle
            debugLine = "Hold the screen toward them"
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
