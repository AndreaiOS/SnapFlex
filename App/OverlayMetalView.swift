// App/OverlayMetalView.swift
import MetalKit
import SwiftUI

struct OverlayMetalView: UIViewRepresentable {
    let driver: OverlayFrameDriver

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: driver.metalDevice)
        view.framebufferOnly = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.preferredFramesPerSecond = 30
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
            descriptor.fragmentFunction = library.makeFunction(name: "overlayFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            renderPipeline = try? driver.metalDevice.makeRenderPipelineState(descriptor: descriptor)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let mask = driver.maskTexture,
                  let renderPipeline,
                  let drawable = view.currentDrawable,
                  let passDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = driver.commandQueue.makeCommandBuffer() else { return }
            passDescriptor.colorAttachments[0].loadAction = .clear
            passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
            encoder.setRenderPipelineState(renderPipeline)
            encoder.setFragmentTexture(mask, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
