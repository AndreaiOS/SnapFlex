// App/LoupeView.swift
import MetalKit
import SwiftUI

/// Focus loupe: reads the bgra8Unorm center-crop texture built by `OverlayPipeline`
/// (a straight blit of the frame's center square) and draws it 1:1 as a magnified
/// preview while a manual focus adjustment is in progress.
struct LoupeView: UIViewRepresentable {
    let driver: OverlayFrameDriver

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: driver.metalDevice)
        view.framebufferOnly = true
        view.isOpaque = true
        view.backgroundColor = .black
        view.isPaused = false
        view.preferredFramesPerSecond = 15
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(driver: driver) }

    final class Coordinator: NSObject, MTKViewDelegate {
        private let driver: OverlayFrameDriver
        private var renderPipeline: MTLRenderPipelineState?

        init(driver: OverlayFrameDriver) {
            self.driver = driver
            super.init()
            guard let library = driver.metalDevice.makeDefaultLibrary() else { return }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "overlayVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "loupeFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = false
            renderPipeline = try? driver.metalDevice.makeRenderPipelineState(descriptor: descriptor)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let loupeTexture = driver.loupeTexture,
                  let renderPipeline,
                  let drawable = view.currentDrawable,
                  let passDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = driver.commandQueue.makeCommandBuffer() else { return }
            passDescriptor.colorAttachments[0].loadAction = .clear
            passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
            encoder.setRenderPipelineState(renderPipeline)
            encoder.setFragmentTexture(loupeTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
