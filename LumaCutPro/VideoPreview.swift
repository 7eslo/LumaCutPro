import SwiftUI
import AVKit

struct VideoPreview: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = AVPlayer(url: url)
        vc.showsPlaybackControls = true
        return vc
    }
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {}
}
