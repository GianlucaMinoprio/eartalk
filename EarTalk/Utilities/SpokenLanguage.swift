import Foundation

/// Languages we pre-select for the other person and for you.
/// Codes match Grok STT / TTS (BCP-47, case-insensitive).
struct SpokenLanguage: Identifiable, Hashable {
    let id: String
    let name: String
    let sttCode: String
    let ttsCode: String

    init(id: String, name: String, sttCode: String? = nil, ttsCode: String? = nil) {
        self.id = id
        self.name = name
        self.sttCode = sttCode ?? id
        self.ttsCode = ttsCode ?? id
    }

    static let catalog: [SpokenLanguage] = [
        SpokenLanguage(id: "en", name: "English"),
        SpokenLanguage(id: "es", name: "Spanish"),
        SpokenLanguage(id: "fr", name: "French"),
        SpokenLanguage(id: "it", name: "Italian"),
        SpokenLanguage(id: "de", name: "German"),
        SpokenLanguage(id: "pt-BR", name: "Portuguese", sttCode: "pt", ttsCode: "pt-BR"),
        SpokenLanguage(id: "zh", name: "Chinese"),
        SpokenLanguage(id: "ja", name: "Japanese"),
        SpokenLanguage(id: "ko", name: "Korean"),
        SpokenLanguage(id: "ar-SA", name: "Arabic", sttCode: "ar", ttsCode: "ar-SA"),
        SpokenLanguage(id: "hi", name: "Hindi"),
        SpokenLanguage(id: "nl", name: "Dutch"),
        SpokenLanguage(id: "ru", name: "Russian"),
        SpokenLanguage(id: "tr", name: "Turkish"),
        SpokenLanguage(id: "pl", name: "Polish"),
        SpokenLanguage(id: "vi", name: "Vietnamese"),
        SpokenLanguage(id: "id", name: "Indonesian"),
        SpokenLanguage(id: "th", name: "Thai")
    ]

    static func named(_ id: String) -> SpokenLanguage {
        catalog.first { $0.id == id } ?? SpokenLanguage(id: id, name: id)
    }
}
