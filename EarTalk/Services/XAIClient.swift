import Foundation

struct AppSettings: Equatable {
    var chatModel: String
    var earVoiceID: String
    var speakerVoiceID: String
    var myLanguage: String
    var theirLanguage: String
    var earVolume: Double
    var speakerVolume: Double

    static let modelAccount = "chat_model"
    static let earVoiceAccount = "ear_voice_id"
    static let speakerVoiceAccount = "speaker_voice_id"
    static let myLanguageAccount = "my_language"
    static let theirLanguageAccount = "their_language"
    static let earVolumeAccount = "ear_volume"
    static let speakerVolumeAccount = "speaker_volume"

    static let defaultChatModel = "grok-4.5"
    static let defaultEarVoice = "eve"
    static let defaultSpeakerVoice = "eve"
    static let defaultMyLanguage = "en"
    static let defaultTheirLanguage = "zh"
    static let defaultEarVolume = 0.85
    static let defaultSpeakerVolume = 0.8

    var hasLiveCredential: Bool {
        SuperGrokSession.isSignedIn
    }

    var myLang: SpokenLanguage { SpokenLanguage.named(myLanguage) }
    var theirLang: SpokenLanguage { SpokenLanguage.named(theirLanguage) }

    static func load() -> AppSettings {
        let earVol = KeychainStore.get(account: earVolumeAccount).flatMap(Double.init)
        let speakVol = KeychainStore.get(account: speakerVolumeAccount).flatMap(Double.init)
        return AppSettings(
            chatModel: KeychainStore.get(account: modelAccount) ?? defaultChatModel,
            earVoiceID: KeychainStore.get(account: earVoiceAccount) ?? defaultEarVoice,
            speakerVoiceID: KeychainStore.get(account: speakerVoiceAccount) ?? defaultSpeakerVoice,
            myLanguage: KeychainStore.get(account: myLanguageAccount) ?? defaultMyLanguage,
            theirLanguage: KeychainStore.get(account: theirLanguageAccount) ?? defaultTheirLanguage,
            earVolume: min(1, max(0.2, earVol ?? defaultEarVolume)),
            speakerVolume: min(1, max(0.2, speakVol ?? defaultSpeakerVolume))
        )
    }

    func save() {
        KeychainStore.set(chatModel, account: Self.modelAccount)
        KeychainStore.set(earVoiceID, account: Self.earVoiceAccount)
        KeychainStore.set(speakerVoiceID, account: Self.speakerVoiceAccount)
        KeychainStore.set(myLanguage, account: Self.myLanguageAccount)
        KeychainStore.set(theirLanguage, account: Self.theirLanguageAccount)
        KeychainStore.set(String(earVolume), account: Self.earVolumeAccount)
        KeychainStore.set(String(speakerVolume), account: Self.speakerVolumeAccount)
    }
}

enum XAIClientError: LocalizedError {
    case missingAPIKey
    case badStatus(Int, String)
    case decodeFailed(String)
    case emptyTranscript
    case emptyTranslation

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Sign in with SuperGrok in Settings."
        case .badStatus(let code, let body):
            return "xAI HTTP \(code): \(body.prefix(280))"
        case .decodeFailed(let detail):
            return "Could not parse xAI response: \(detail)"
        case .emptyTranscript:
            return "STT returned empty text. Try again closer to the mic."
        case .emptyTranslation:
            return "Model returned an empty translation."
        }
    }
}

struct STTResult: Equatable {
    let text: String
    let language: String?
}

actor XAIClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.x.ai/v1")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - STT

    func transcribe(fileURL: URL, bearer: String, language: String?) async throws -> STTResult {
        let bearer = bearer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bearer.isEmpty else { throw XAIClientError.missingAPIKey }

        var request = URLRequest(url: baseURL.appendingPathComponent("stt"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mime = mimeType(for: fileURL)

        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        // Options must precede file. Language is formatting only; the model
        // already transcribes any supported language without it.
        if let language {
            let language = language.trimmingCharacters(in: .whitespacesAndNewlines)
            if !language.isEmpty {
                appendField(name: "language", value: language)
                appendField(name: "format", value: "true")
            }
        }
        request.timeoutInterval = 12

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try throwIfNeeded(data: data, response: response)

        let decoded = try JSONDecoder().decode(STTResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw XAIClientError.emptyTranscript }
        return STTResult(text: text, language: decoded.language)
    }

    // MARK: - Translate

    func translate(
        text: String,
        from: SpokenLanguage,
        to: SpokenLanguage,
        bearer: String,
        model: String
    ) async throws -> String {
        let bearer = bearer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bearer.isEmpty else { throw XAIClientError.missingAPIKey }

        if from.matches(to.id) || from.id == to.id {
            return text
        }

        let system = "Translate from \(from.name) to \(to.name). Reply with the spoken translation only. No quotes, no notes, no romanization."

        var payload: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "max_tokens": 220,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text]
            ]
        ]
        if !model.contains("non-reasoning") {
            payload["reasoning_effort"] = "low"
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        try throwIfNeeded(data: data, response: response)

        let chat = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = chat.choices.first?.message.content else {
            throw XAIClientError.decodeFailed("missing choices")
        }

        let translation = try parseTranslation(from: content)
        guard !translation.isEmpty else { throw XAIClientError.emptyTranslation }
        return translation
    }

    // MARK: - TTS

    func synthesize(text: String, bearer: String, voiceID: String, language: String) async throws -> Data {
        guard !bearer.isEmpty else { throw XAIClientError.missingAPIKey }

        let payload: [String: Any] = [
            "text": text,
            "voice_id": voiceID,
            "language": language,
            "output_format": [
                "codec": "mp3",
                "sample_rate": 24_000,
                "bit_rate": 64_000
            ],
            "speed": 1.05
        ]

        var request = URLRequest(url: baseURL.appendingPathComponent("tts"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        try throwIfNeeded(data: data, response: response, expectJSONErrorOnly: true)

        guard !data.isEmpty else {
            throw XAIClientError.decodeFailed("empty TTS audio")
        }
        return data
    }

    // MARK: - Helpers

    private func parseTranslation(from content: String) throws -> String {
        var trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            trimmed = trimmed
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.first == "{",
           let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}"),
           start < end,
           let payload = try? JSONDecoder().decode(
            TranslationDTO.self,
            from: Data(trimmed[start...end].utf8)
           ) {
            trimmed = payload.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
            || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func throwIfNeeded(data: Data, response: URLResponse, expectJSONErrorOnly: Bool = false) throws {
        guard let http = response as? HTTPURLResponse else {
            throw XAIClientError.decodeFailed("invalid HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
            throw XAIClientError.badStatus(http.statusCode, body)
        }
        if expectJSONErrorOnly {
            return
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a": return "audio/m4a"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "caf": return "audio/x-caf"
        default: return "application/octet-stream"
        }
    }
}

private struct STTResponse: Decodable {
    let text: String
    let duration: Double?
    let language: String?
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct TranslationDTO: Decodable {
    let translation: String
}
