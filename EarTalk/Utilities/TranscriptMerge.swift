import Foundation

/// Merge overlapping live STT fragments. Keep short CJK replies.
enum TranscriptMerge {
    static func cleaned(_ piece: String) -> String {
        piece.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isUsable(_ piece: String) -> Bool {
        let piece = cleaned(piece)
        guard !piece.isEmpty else { return false }
        if piece.unicodeScalars.contains(where: { $0.value >= 0x0400 }) {
            return piece.count >= 1
        }
        return piece.count >= 2
    }

    static func append(existing: String, incoming: String) -> String {
        let incoming = cleaned(incoming)
        guard isUsable(incoming) else { return existing }
        if existing.isEmpty { return incoming }
        if existing.localizedCaseInsensitiveContains(incoming) { return existing }
        if incoming.localizedCaseInsensitiveContains(existing) { return incoming }

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
}
