import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class SpeechPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?
    private var volumeView: MPVolumeView?

    func play(data: Data, route: AudioRoute, volume: Float = 0.7) async throws {
        stop()
        switch route {
        case .earbuds:
            if Headphones.areWorn() {
                try AudioRouter.configure(for: .playEar, deactivateFirst: false)
            } else {
                try AudioRouter.configure(for: .playSpeaker, deactivateFirst: false)
            }
        case .speaker:
            try AudioRouter.configure(for: .playSpeaker, deactivateFirst: false)
            raiseSystemVolume(to: max(0.2, min(1, volume)))
        }

        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.volume = max(0.2, min(1, volume))
        player.prepareToPlay()
        self.player = player
        isPlaying = true
        player.play()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        continuation?.resume()
        continuation = nil
    }

    /// Bump the phone media volume so someone nearby can hear the translation.
    private func raiseSystemVolume(to target: Float) {
        let current = AVAudioSession.sharedInstance().outputVolume
        guard current + 0.02 < target else { return }
        if volumeView == nil {
            let view = MPVolumeView(frame: CGRect(x: -2000, y: -2000, width: 10, height: 10))
            view.alpha = 0.01
            volumeView = view
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }?
                .addSubview(view)
        }
        guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = target
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.continuation?.resume()
            self.continuation = nil
        }
    }
}
