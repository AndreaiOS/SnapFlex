import AVFoundation
import AVKit
import SwiftUI

struct PreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    var onCaptureEvent: () -> Void = {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        let interaction = AVCaptureEventInteraction { event in
            if event.phase == .began { self.onCaptureEvent() }
        }
        view.addInteraction(interaction)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}
