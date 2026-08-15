import CoreImage
import MetalKit
import SwiftUI

struct FilteredCameraPreviewView: UIViewRepresentable {
    let output: LiveFilterPreviewOutput
    
    func makeUIView(context: Context) -> FilteredCameraPreviewUIView {
        FilteredCameraPreviewUIView(output: output)
    }
    
    func updateUIView(_ uiView: FilteredCameraPreviewUIView, context: Context) {
        uiView.attach(to: output)
    }
    
    static func dismantleUIView(_ uiView: FilteredCameraPreviewUIView, coordinator: ()) {
        uiView.detach()
    }
}

final class FilteredCameraPreviewUIView: UIView {
    private let renderer: LiveFilterPreviewRenderer?
    private weak var output: LiveFilterPreviewOutput?
    
    init(output: LiveFilterPreviewOutput) {
        self.output = output
        
        if let device = MTLCreateSystemDefaultDevice(),
           let renderer = LiveFilterPreviewRenderer(device: device) {
            self.renderer = renderer
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            
            let metalView = renderer.view
            metalView.isUserInteractionEnabled = false
            metalView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(metalView)
            NSLayoutConstraint.activate([
                metalView.leadingAnchor.constraint(equalTo: leadingAnchor),
                metalView.trailingAnchor.constraint(equalTo: trailingAnchor),
                metalView.topAnchor.constraint(equalTo: topAnchor),
                metalView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
            output.setRenderer(renderer)
        } else {
            self.renderer = nil
            super.init(frame: .zero)
            backgroundColor = .clear
        }
    }
    
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func attach(to output: LiveFilterPreviewOutput) {
        self.output = output
        output.setRenderer(renderer)
    }
    
    func detach() {
        output?.setRenderer(nil)
        renderer?.clear()
    }
}

final class LiveFilterPreviewRenderer: NSObject, MTKViewDelegate, LiveFilterPreviewFrameRenderer, @unchecked Sendable {
    let view: MTKView
    
    private let commandQueue: MTLCommandQueue
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private let filterRenderer = PhotoFilterLiveRenderer()
    private let lock = NSLock()
    nonisolated(unsafe) private var latestImage: CIImage?
    nonisolated(unsafe) private var latestFilter: PhotoFilter = .off
    nonisolated(unsafe) private var latestRetroMegaPixels: Float = 0.3
    nonisolated(unsafe) private var latestReferenceSize: CGSize = .zero
    nonisolated(unsafe) private var isDrawScheduled = false
    
    init?(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue() else { return nil }
        
        self.commandQueue = commandQueue
        self.context = CIContext(mtlDevice: device)
        self.view = MTKView(frame: .zero, device: device)
        super.init()
        
        view.delegate = self
        view.framebufferOnly = false
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30
        view.colorPixelFormat = .bgra8Unorm
        view.isOpaque = false
        view.layer.isOpaque = false
        if let metalLayer = view.layer as? CAMetalLayer {
            metalLayer.isOpaque = false
        }
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.contentMode = .scaleAspectFit
    }
    
    nonisolated func render(pixelBuffer: CVPixelBuffer, filter: PhotoFilter, retroMegaPixels: Float, referenceSize: CGSize) {
        guard filter != .off else { return }
        
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        lock.lock()
        latestImage = image
        latestFilter = filter
        latestRetroMegaPixels = retroMegaPixels
        latestReferenceSize = referenceSize
        guard !isDrawScheduled else {
            lock.unlock()
            return
        }
        isDrawScheduled = true
        lock.unlock()
        
        Task { @MainActor in
            self.view.draw()
        }
    }
    
    func clear() {
        lock.lock()
        latestImage = nil
        latestFilter = .off
        latestRetroMegaPixels = 0.3
        latestReferenceSize = .zero
        isDrawScheduled = false
        lock.unlock()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        lock.lock()
        let sourceImage = latestImage
        let filter = latestFilter
        let retroMegaPixels = latestRetroMegaPixels
        let referenceSize = latestReferenceSize
        isDrawScheduled = false
        lock.unlock()
        
        guard let sourceImage,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        
        let drawableSize = view.drawableSize
        let bounds = CGRect(origin: .zero, size: drawableSize)
        guard bounds.width > 0, bounds.height > 0 else { return }
        
        let filteredImage = filterRenderer.filteredImage(
            from: sourceImage,
            filter: filter,
            retroMegaPixels: retroMegaPixels,
            referenceSize: referenceSize
        ) ?? sourceImage
        let fittedImage = fit(filteredImage, in: bounds)
        let clearBg = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: bounds)
        let outputImage = fittedImage.composited(over: clearBg)
        
        context.render(
            outputImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: bounds,
            colorSpace: colorSpace
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func fit(_ image: CIImage, in bounds: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        
        let scale = min(bounds.width / extent.width, bounds.height / extent.height)
        let scaledWidth = extent.width * scale
        let scaledHeight = extent.height * scale
        let x = bounds.midX - scaledWidth / 2
        let y = bounds.midY - scaledHeight / 2
        
        return image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: x, y: y))
            .cropped(to: bounds)
    }
}
