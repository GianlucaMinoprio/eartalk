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
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
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

enum Headphones {
    /// True only when buds are actually on the current route or offered as an input.
    /// In the case they disappear. Do not IMU-gate EarTalk on this.
    static func areWorn() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let budPorts: Set<AVAudioSession.Port> = [
            .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .headsetMic
        ]
        if session.currentRoute.outputs.contains(where: { budPorts.contains($0.portType) }) {
            return true
        }
        if session.currentRoute.inputs.contains(where: { budPorts.contains($0.portType) }) {
            return true
        }
        if session.availableInputs?.contains(where: { budPorts.contains($0.portType) }) == true {
            return true
        }
        return false
    }
}

enum AudioRouter {
    static func configure(for scene: AudioScene, deactivateFirst: Bool = true) throws {
        let session = AVAudioSession.sharedInstance()
        let buds = Headphones.areWorn()
        if deactivateFirst {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }

        switch scene {
        case .listenThem:
            // Built-in mic hears them. Never the AirPods mic.
            var options: AVAudioSession.CategoryOptions = []
            if buds {
                options.insert(.allowBluetoothA2DP)
            } else {
                options.insert(.defaultToSpeaker)
            }
            try session.setCategory(.playAndRecord, mode: .default, options: options)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            if buds {
                try session.overrideOutputAudioPort(.none)
            } else {
                try session.overrideOutputAudioPort(.speaker)
            }
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            }
        case .listenMe:
            if buds {
                try session.setCategory(
                    .playAndRecord,
                    mode: .spokenAudio,
                    options: [.allowBluetooth, .allowBluetoothA2DP]
                )
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                try session.overrideOutputAudioPort(.none)
                if let budsIn = session.availableInputs?.first(where: {
                    $0.portType == .bluetoothHFP || $0.portType == .headsetMic
                }) {
                    try? session.setPreferredInput(budsIn)
                }
            } else {
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
        case .playEar:
            if buds {
                try session.setCategory(
                    .playAndRecord,
                    mode: .spokenAudio,
                    options: [.allowBluetoothA2DP, .allowBluetooth]
                )
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                try session.overrideOutputAudioPort(.none)
            } else {
                try configure(for: .playSpeaker)
            }
        case .playSpeaker:
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
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
