import Foundation
import AVFoundation
import QuartzCore

/// Video wallpaper backend: seamless looping playback via AVPlayerLooper
/// on an AVQueuePlayer, hardware-decoded, rendered into an AVPlayerLayer.
public final class VideoWallpaperEngine: WallpaperEngine {
    private let player: AVQueuePlayer
    private let playerLayer: AVPlayerLayer
    private var looper: AVPlayerLooper?

    public var layer: CALayer { playerLayer }

    public init(fileURL: URL, muted: Bool = true, fillMode: AVLayerVideoGravity = .resizeAspectFill) throws {
        let asset = AVURLAsset(url: fileURL)
        let item = AVPlayerItem(asset: asset)
        player = AVQueuePlayer()
        player.isMuted = muted
        // Looping requires the item registered as a template before play.
        looper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer = AVPlayerLayer()
        playerLayer.player = player
        playerLayer.videoGravity = fillMode
    }

    public func start() {
        player.play()
    }

    public func pause() {
        player.pause()
    }

    public func resume() {
        player.play()
    }

    public func stop() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        playerLayer.player = nil
    }

    public func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }
}
