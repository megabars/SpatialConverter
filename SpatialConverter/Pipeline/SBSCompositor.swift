import CoreImage
import CoreVideo
import Metal

/// GPU-accelerated side-by-side compositor using Metal-backed CIContext.
/// Thread-safe after initialization (immutable state).
final class SBSCompositor: Sendable {

    private let ciContext: CIContext
    static let outputSize = CGSize(width: 3840, height: 1080)
    static let outputRect = CGRect(origin: .zero, size: outputSize)
    private static let colorSpace = CGColorSpaceCreateDeviceRGB()

    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            ciContext = CIContext(mtlDevice: device, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
                .outputColorSpace:  CGColorSpace(name: CGColorSpace.sRGB) as Any,
                .useSoftwareRenderer: false
            ])
        } else {
            ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }
    }

    // MARK: - Compose two eye buffers into a 3840x1080 SBS frame

    func compose(left: CVPixelBuffer, right: CVPixelBuffer) -> CIImage {
        let leftImage  = CIImage(cvPixelBuffer: left)
        let rightImage = CIImage(cvPixelBuffer: right)

        let halfW  = Self.outputSize.width / 2   // 1920
        let height = Self.outputSize.height       // 1080

        // Scale each eye to exactly 1920x1080 (source should already be this size)
        let scaleL = CGAffineTransform(
            scaleX: halfW / leftImage.extent.width,
            y: height / leftImage.extent.height
        )
        let scaleR = CGAffineTransform(
            scaleX: halfW / rightImage.extent.width,
            y: height / rightImage.extent.height
        )

        let scaledLeft  = leftImage.transformed(by: scaleL)
        // Right eye goes at X offset 1920
        let scaledRight = rightImage
            .transformed(by: scaleR)
            .transformed(by: CGAffineTransform(translationX: halfW, y: 0))

        let background = CIImage(color: CIColor.black)
            .cropped(to: Self.outputRect)

        return scaledRight
            .composited(over: scaledLeft)
            .composited(over: background)
    }

    // MARK: - Render composed image into a pixel buffer

    func render(image: CIImage, into pixelBuffer: CVPixelBuffer) {
        ciContext.render(
            image,
            to: pixelBuffer,
            bounds: Self.outputRect,
            colorSpace: Self.colorSpace
        )
    }

    // MARK: - Convenience: compose + render in one call

    func composeAndRender(
        left: CVPixelBuffer,
        right: CVPixelBuffer,
        into pixelBuffer: CVPixelBuffer
    ) {
        let composed = compose(left: left, right: right)
        render(image: composed, into: pixelBuffer)
    }
}
