// App/LongPreviewMetalView.swift
import MetalKit
import SwiftUI

struct LongPreviewMetalView: UIViewRepresentable {
    let controller: LongExposureController

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: controller.metalDevice)
        view.framebufferOnly = true
        view.isOpaque = true
        view.backgroundColor = .black
        view.preferredFramesPerSecond = 30
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    final class Coordinator: NSObject, MTKViewDelegate {
        private let controller: LongExposureController
        private var renderPipeline: MTLRenderPipelineState?

        init(controller: LongExposureController) {
            self.controller = controller
            super.init()
            guard let library = controller.metalDevice.makeDefaultLibrary() else { return }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "longVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "accumulationFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = false
            renderPipeline = try? controller.metalDevice.makeRenderPipelineState(descriptor: descriptor)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let previewTexture = controller.previewTexture,
                  let renderPipeline,
                  let drawable = view.currentDrawable,
                  let passDescriptor = view.currentRenderPassDescriptor,
                  let commandBuffer = controller.commandQueue.makeCommandBuffer() else { return }
            passDescriptor.colorAttachments[0].loadAction = .clear
            passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
            encoder.setRenderPipelineState(renderPipeline)
            encoder.setFragmentTexture(previewTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
