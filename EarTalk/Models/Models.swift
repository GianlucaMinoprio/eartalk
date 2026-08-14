import Foundation
import SwiftUI

enum SessionPhase: Equatable {
    case idle
    case hearingThem
    case transcribingThem
    case translatingThem
    case playingEar
    case hearingMe
    case transcribingMe
    case translatingMe
    case playingSpeaker
    case error(String)

    var shortLabel: String {
        switch self {
        case .idle: return "Ready"
        case .hearingThem: return "Hearing them"
        case .transcribingThem: return "Transcribing them"
        case .translatingThem: return "Translating to you"
        case .playingEar: return "In your ear"
        case .hearingMe: return "Hearing you"
        case .transcribingMe: return "Transcribing you"
        case .translatingMe: return "Translating out"
        case .playingSpeaker: return "Speaking out"
        case .error: return "Error"
        }
    }

    var symbolName: String {
        switch self {
        case .idle: return "checkmark.circle"
        case .hearingThem: return "ear.fill"
        case .transcribingThem, .transcribingMe: return "waveform"
        case .translatingThem, .translatingMe: return "globe"
        case .playingEar: return "airpodspro"
        case .hearingMe: return "mic.fill"
        case .playingSpeaker: return "speaker.wave.2.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle: return .secondary
        case .hearingThem, .hearingMe: return .red
        case .transcribingThem, .transcribingMe, .translatingThem, .translatingMe: return .orange
        case .playingEar: return .accentColor
        case .playingSpeaker: return .blue
        case .error: return .orange
        }
    }

    var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }

    var isBusy: Bool {
        switch self {
        case .transcribingThem, .translatingThem, .playingEar,
             .transcribingMe, .translatingMe, .playingSpeaker:
            return true
        default:
            return false
        }
    }

    var isCapturing: Bool {
        switch self {
        case .hearingThem, .hearingMe:
            return true
        default:
            return false
        }
    }
}

enum TalkDirection: String, Equatable {
    case themToMe
    case meToThem
}

struct ConversationTurn: Identifiable, Equatable {
    let id: UUID
    let direction: TalkDirection
    let sourceText: String
    let translatedText: String
    let sourceLanguage: String
    let targetLanguage: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        direction: TalkDirection,
        sourceText: String,
        translatedText: String,
        sourceLanguage: String,
        targetLanguage: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.direction = direction
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.createdAt = createdAt
    }
}

enum DeviceEnvironment {
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
