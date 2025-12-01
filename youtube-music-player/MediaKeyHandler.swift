import Foundation
import MediaPlayer
import AppKit

@Observable
@MainActor
class MediaKeyHandler {
    private var viewModel: YouTubeMusicViewModel?
    private var currentArtwork: NSImage?

    init() {
        setupRemoteCommandCenter()
        becomeNowPlaying()
    }

    func setViewModel(_ viewModel: YouTubeMusicViewModel) {
        self.viewModel = viewModel
        viewModel.onTrackChange = { [weak self] title, artist, artworkUrl, isPlaying in
            self?.updateNowPlaying(title: title, artist: artist, artworkUrl: artworkUrl, isPlaying: isPlaying)
        }
    }

    private func becomeNowPlaying() {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = "YouTube Music"
        nowPlayingInfo[MPMediaItemPropertyArtist] = ""
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    private func updateNowPlaying(title: String?, artist: String?, artworkUrl: URL?, isPlaying: Bool) {
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? "YouTube Music"
        nowPlayingInfo[MPMediaItemPropertyArtist] = artist ?? ""
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        if let url = artworkUrl {
            Task.detached {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = NSImage(data: data) {
                        await MainActor.run { [weak self] in
                            self?.currentArtwork = image
                            let artwork = MPMediaItemArtwork(boundsSize: image.size) { [weak self] _ in
                                return self?.currentArtwork ?? NSImage()
                            }
                            var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                            updatedInfo[MPMediaItemPropertyArtwork] = artwork
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                        }
                    }
                } catch {}
            }
        }
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.playPause()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.playPause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.playPause()
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.nextTrack()
            }
            return .success
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.viewModel?.previousTrack()
            }
            return .success
        }

        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
    }
}
