import AVFoundation
import CoreMedia
import CoreVideo

// Stereo frame pair ready for SBS compositing
struct StereoFramePair: @unchecked Sendable {
    let left: CVPixelBuffer
    let right: CVPixelBuffer
    let presentationTime: CMTime
    let frameIndex: Int
}

enum DecoderError: Error, LocalizedError {
    case readerFailed(Error?)
    case noSampleBuffer
    case missingImageBuffer
    case rightViewNotFound
    case setupFailed(String)

    var errorDescription: String? {
        switch self {
        case .readerFailed(let e):    return "Ошибка чтения: \(e?.localizedDescription ?? "неизвестно")"
        case .missingImageBuffer:     return "Не удалось получить кадр из буфера"
        case .rightViewNotFound:      return "Правый вид не найден — будет использован ffmpeg"
        case .setupFailed(let msg):   return "Ошибка инициализации декодера: \(msg)"
        case .noSampleBuffer:         return "Буфер кадра недоступен"
        }
    }
}

// MARK: - CMTaggedBufferGroup bridge
// These functions exist in the CoreMedia binary (macOS 14+) but are not yet
// surfaced in Swift module headers; @_silgen_name links to the C symbol directly.

@_silgen_name("CMSampleBufferGetTaggedBufferGroup")
private func _sampleBufferGetTaggedGroup(
    _ buf: CMSampleBuffer
) -> Unmanaged<AnyObject>?          // CF_RETURNS_NOT_RETAINED

@_silgen_name("CMTaggedBufferGroupGetCount")
private func _taggedGroupGetCount(_ group: AnyObject) -> Int

@_silgen_name("CMTaggedBufferGroupGetCVPixelBufferAtIndex")
private func _taggedGroupGetPixelBuffer(
    _ group: AnyObject,
    _ index: Int
) -> Unmanaged<CVPixelBuffer>?      // CF_RETURNS_NOT_RETAINED

// MARK: -

/// Pull-based stereo decoder. Call setup() once, then nextFrame() in a loop,
/// then teardown(). No internal buffer — the caller controls pacing.
actor SpatialVideoDecoder {

    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var firstFrameChecked = false

    // MARK: - Lifecycle

    func setup(asset: AVURLAsset, videoTrack: AVAssetTrack) throws {
        let r = try AVAssetReader(asset: asset)
        let o = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: makeOutputSettings()
        )
        o.alwaysCopiesSampleData = false
        guard r.canAdd(o) else {
            throw DecoderError.setupFailed("canAdd output = false")
        }
        r.add(o)
        r.startReading()
        reader = r
        output = o
        firstFrameChecked = false
    }

    func teardown() {
        reader?.cancelReading()
        reader = nil
        output = nil
    }

    // MARK: - Pull one frame

    /// Returns the next stereo pair, or nil when the stream is exhausted.
    /// Throws DecoderError.rightViewNotFound on the very first frame if stereo
    /// extraction fails, so the pipeline can switch to ffmpeg immediately.
    func nextFrame(index: Int) throws -> StereoFramePair? {
        guard let r = reader, r.status == .reading else {
            if reader?.status == .failed {
                throw DecoderError.readerFailed(reader?.error)
            }
            return nil
        }
        guard let sample = output?.copyNextSampleBuffer() else { return nil }

        do {
            let pair = try extractStereoViews(from: sample, index: index)
            firstFrameChecked = true
            return pair
        } catch DecoderError.rightViewNotFound where !firstFrameChecked {
            throw DecoderError.rightViewNotFound
        } catch {
            return nil  // skip unextractable frames after first-frame check
        }
    }

    // MARK: - Output settings

    nonisolated private func makeOutputSettings() -> [String: Any] {
        [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            AVVideoDecompressionPropertiesKey: [
                "RequestedMVHEVCVideoLayerIDs": [NSNumber(value: 0), NSNumber(value: 1)]
            ] as [String: Any]
        ]
    }

    // MARK: - Stereo extraction

    nonisolated private func extractStereoViews(
        from sampleBuffer: CMSampleBuffer,
        index: Int
    ) throws -> StereoFramePair {

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // ── Method 1: CMTaggedBufferGroup (macOS 14+ MV-HEVC delivery) ────────
        if let groupRef = _sampleBufferGetTaggedGroup(sampleBuffer) {
            let group = groupRef.takeUnretainedValue()
            if _taggedGroupGetCount(group) >= 2,
               let left  = _taggedGroupGetPixelBuffer(group, 0)?.takeUnretainedValue(),
               let right = _taggedGroupGetPixelBuffer(group, 1)?.takeUnretainedValue() {
                if index == 0 {
                    print("✅ [SpatialVideoDecoder] CMTaggedBufferGroup: оба слоя извлечены")
                }
                return StereoFramePair(
                    left: left, right: right,
                    presentationTime: pts, frameIndex: index
                )
            }
        }

        // ── Method 2: CMSampleBuffer attachment (legacy path) ─────────────────
        guard let leftBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw DecoderError.rightViewNotFound
        }
        let key = "StereoscopicRightEyeBuffer" as CFString
        if let rightRef = CMGetAttachment(sampleBuffer, key: key, attachmentModeOut: nil) {
            let right = unsafeBitCast(rightRef, to: CVPixelBuffer.self)
            return StereoFramePair(
                left: leftBuffer, right: right,
                presentationTime: pts, frameIndex: index
            )
        }

        throw DecoderError.rightViewNotFound
    }
}
