import AVFoundation
import Foundation

enum CaptureMic {
    /// Point the phone at them. Never use AirPods mic here.
    case them
    /// You are speaking. AirPods mic is fine if present.
    case me
}

@MainActor
final class AudioCaptureService: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var lastError: String?
    @Published private(set) var averagePower: Float = -80

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var meterTimer: Timer?

    func requestPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    cont.resume(returning: allowed)
                }
            }
        }
    }

    func start(mic: CaptureMic) throws {
        lastError = nil
        try AudioRouter.configure(for: mic == .them ? .listenThem : .listenMe)
        try beginFile()
    }

    /// Close the current file and immediately open a new one (live STT chunks).
    func rotate() throws -> URL? {
        let finished = finishCurrentFile()
        try beginFile()
        return finished
    }

    func stop() -> URL? {
        let url = finishCurrentFile()
        isRecording = false
        return url
    }

    func updateMeters() {
        recorder?.updateMeters()
        averagePower = recorder?.averagePower(forChannel: 0) ?? -80
    }

    private func beginFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eartalk-\(UUID().uuidString).m4a")
        fileURL = url
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw CaptureError.failedToStart }
        self.recorder = recorder
        isRecording = true
        startMeterTimer()
    }

    private func finishCurrentFile() -> URL? {
        meterTimer?.invalidate()
        meterTimer = nil
        guard recorder != nil else { return nil }
        recorder?.stop()
        recorder = nil
        let url = fileURL
        fileURL = nil
        return url
    }

    private func startMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMeters()
            }
        }
    }

    enum CaptureError: LocalizedError {
        case failedToStart
        var errorDescription: String? { "Could not start microphone capture." }
    }
}

enum AudioRoute {
    case earbuds
    case speaker
}

enum AudioScene {
    case listenThem
    case listenMe
    case playEar
    case playSpeaker
}

enum AudioRouter {
    static func configure(for scene: AudioScene) throws {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        switch scene {
        case .listenThem:
            // Built-in mic hears them. Playback later goes to AirPods.
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetoothA2DP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try session.overrideOutputAudioPort(.none)
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            }
        case .listenMe:
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try session.overrideOutputAudioPort(.none)
            if let buds = session.availableInputs?.first(where: {
                $0.portType == .bluetoothHFP || $0.portType == .headsetMic
            }) {
                try? session.setPreferredInput(buds)
            }
        case .playEar:
            try session.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.allowBluetoothA2DP, .allowBluetooth]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try session.overrideOutputAudioPort(.none)
        case .playSpeaker:
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            try session.overrideOutputAudioPort(.speaker)
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            }
        }
    }
}
