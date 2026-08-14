import Foundation

/// Decide if the last utterance was them or you.
/// Primary signal: Grok STT language vs the two pre-selected languages.
/// Backup: script (CJK, Arabic, etc.) when STT omits a language tag.
enum SpeakerSense {
    static func direction(
        text: String,
        detectedLanguage: String?,
        my: SpokenLanguage,
        their: SpokenLanguage
    ) -> (TalkDirection, String) {
        if let detectedLanguage {
            let theirs = their.matches(detectedLanguage)
            let mine = my.matches(detectedLanguage)
            if theirs && !mine {
                return (.themToMe, "Sounds like \(their.name). That's them.")
            }
            if mine && !theirs {
                return (.meToThem, "Sounds like \(my.name). That's you.")
            }
        }

        if let script = scriptHint(in: text) {
            if their.matches(script) && !my.matches(script) {
                return (.themToMe, "Script looks like \(their.name). That's them.")
            }
            if my.matches(script) && !their.matches(script) {
                return (.meToThem, "Script looks like \(my.name). That's you.")
            }
        }

        return (.themToMe, "Not sure. Treating this as them. Force I speak if that was you.")
    }
}

extension SpokenLanguage {
    func matches(_ raw: String) -> Bool {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !code.isEmpty else { return false }
        let id = id.lowercased()
        let stt = sttCode.lowercased()
        let tts = ttsCode.lowercased()
        if code == id || code == stt || code == tts { return true }
        if code.hasPrefix(id + "-") || code.hasPrefix(stt + "-") { return true }
        let short = String(code.prefix(2))
        if short == String(id.prefix(2)) || short == String(stt.prefix(2)) { return true }
        return false
    }
}

private func scriptHint(in text: String) -> String? {
    var han = 0, hira = 0, kata = 0, hangul = 0, arabic = 0, cyrillic = 0, devanagari = 0, thai = 0
    for scalar in text.unicodeScalars {
        switch scalar.value {
        case 0x3040...0x309F: hira += 1
        case 0x30A0...0x30FF: kata += 1
        case 0x4E00...0x9FFF: han += 1
        case 0xAC00...0xD7AF: hangul += 1
        case 0x0600...0x06FF, 0x0750...0x077F: arabic += 1
        case 0x0400...0x04FF: cyrillic += 1
        case 0x0900...0x097F: devanagari += 1
        case 0x0E00...0x0E7F: thai += 1
        default: break
        }
    }
    let ranked: [(Int, String)] = [
        (hira + kata, "ja"),
        (hangul, "ko"),
        (han, "zh"),
        (arabic, "ar"),
        (cyrillic, "ru"),
        (devanagari, "hi"),
        (thai, "th")
    ]
    return ranked.max(by: { $0.0 < $1.0 }).flatMap { $0.0 >= 2 ? $0.1 : nil }
}
