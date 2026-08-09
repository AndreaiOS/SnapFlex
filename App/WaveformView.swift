// App/WaveformView.swift
import MetalKit
import SwiftUI

/// Docked luma waveform monitor: reads the r32Uint waveform texture (column = tone,
/// row = brightness bucket, value = pixel count) built by `OverlayPipeline` and
/// draws it as a green-on-black scope. Raw integer reads only — no sampler.
struct WaveformView: UIViewRepresentable {
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
            descriptor.fragmentFunction = library.makeFunction(name: "waveformFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = false
            renderPipeline = try? driver.metalDevice.makeRenderPipelineState(descriptor: descriptor)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let waveformTexture = driver.waveformTexture,
                  let renderPipeline,
                  let drawable = view.currentDrawable,
                  let passDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = driver.commandQueue.makeCommandBuffer() else { return }
            passDescriptor.colorAttachments[0].loadAction = .clear
            passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
            encoder.setRenderPipelineState(renderPipeline)
            encoder.setFragmentTexture(waveformTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
