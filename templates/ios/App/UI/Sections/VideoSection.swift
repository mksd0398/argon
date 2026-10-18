import AVKit
import ArgonUI
import SwiftUI

/// A video's width to height for its `aspect` setting.
func videoRatio(_ aspect: String) -> CGFloat {
    switch aspect {
    case "9:16": return 9.0 / 16
    case "1:1": return 1
    case "4:5": return 0.8
    default: return 16.0 / 9
    }
}

/// `video`: an https MP4 or HLS stream in the system player, in a box of `aspect`. With `autoplay` it plays as it shows
/// (muted while `muted`) and pauses when it goes; without, the `poster` shows with a play button until it is tapped.
/// `loop` starts it over at the end.
@MainActor
struct VideoSection: View {
    let settings: SectionSettings
    @State private var player: AVPlayer? = nil
    @State private var started = false
    @Environment(\.argonTheme) private var theme

    var body: some View {
        let link = settings.text("url").flatMap { URL(string: $0) }
        if let url = link, url.scheme?.lowercased() == "https" {
            let autoplay = settings.boolean("autoplay", true)
            Color.black
                .aspectRatio(videoRatio(settings.choice("aspect", ["16:9", "9:16", "1:1", "4:5"], "16:9")), contentMode: .fit)
                .overlay {
                    if let player = player { VideoPlayer(player: player) }
                }
                .overlay {
                    if !autoplay && !started { poster }
                }
                .onAppear {
                    let shown = player ?? AVPlayer(url: url)
                    shown.isMuted = settings.boolean("muted", true)
                    player = shown
                    if autoplay || started { shown.play() }
                }
                .onDisappear { player?.pause() }
                .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
                    guard settings.boolean("loop", true), let player = player, (note.object as? AVPlayerItem) === player.currentItem else { return }
                    player.seek(to: .zero)
                    player.play()
                }
        }
    }

    private var poster: some View {
        Button {
            started = true
            player?.play()
        } label: {
            StoreImage(image: settings.image("poster"))
                .overlay {
                    ArgonIcon(name: .play, size: 32, tint: .white)
                        .padding(theme.spacing.m)
                        .background(.black.opacity(0.5), in: Circle())
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play video")
    }
}
