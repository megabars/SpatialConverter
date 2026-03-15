import AVFoundation
import CoreVideo
import CoreMedia

enum EncoderError: Error, LocalizedError {
    case writerCreationFailed(Error)
    case pixelBufferPoolUnavailable
    case pixelBufferAllocationFailed(CVReturn)
    case encodingFailed(Error?)
    case outputFileExists

    var errorDescription: String? {
        switch self {
        case .writerCreationFailed(let e):          return "Не удалось создать encoder: \(e.localizedDescription)"
        case .pixelBufferPoolUnavailable:            return "Пул пиксельных буферов недоступен"
        case .pixelBufferAllocationFailed(let code):return "Ошибка выделения буфера: \(code)"
        case .encodingFailed(let e):                return "Ошибка энкодинга: \(e?.localizedDescription ?? "неизвестно")"
        case .outputFileExists:                     return "Выходной файл уже существует"
        }
    }
}

struct EncoderSession {
    let writer: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let audioInput: AVAssetWriterInput?
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
}

actor SBSEncoder {

    func makeSession(
        outputURL: URL,
        settings: ConversionSettings,
        info: SpatialVideoInfo
    ) throws -> EncoderSession {
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw EncoderError.writerCreationFailed(error)
        }

        // ── Video input ───────────────────────────────────────────────────────
        let fps = Double(info.nominalFrameRate)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: settings.videoCodec.avCodecType,
            AVVideoWidthKey:  SBSCompositor.outputSize.width,
            AVVideoHeightKey: SBSCompositor.outputSize.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey:     AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey:   AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey:        AVVideoYCbCrMatrix_ITU_R_709_2
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:             settings.qualityPreset.bitrate(for: settings.videoCodec),
                AVVideoExpectedSourceFrameRateKey:    fps,
                AVVideoMaxKeyFrameIntervalKey:        Int(fps * 2),
                AVVideoAllowFrameReorderingKey:       true
            ]
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.mediaTimeScale = CMTimeScale(600) // common timebase

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey  as String: Int(SBSCompositor.outputSize.width),
                kCVPixelBufferHeightKey as String: Int(SBSCompositor.outputSize.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
            ]
        )

        guard writer.canAdd(videoInput) else {
            throw EncoderError.writerCreationFailed(NSError(domain: "Encoder", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "canAdd videoInput = false"]))
        }
        writer.add(videoInput)

        // ── Audio input (passthrough) ─────────────────────────────────────────
        var audioInput: AVAssetWriterInput? = nil
        if settings.audioPassthrough && info.audioTrackIndex != nil {
            let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            ai.expectsMediaDataInRealTime = false
            if writer.canAdd(ai) {
                writer.add(ai)
                audioInput = ai
            }
        }

        writer.shouldOptimizeForNetworkUse = true // faststart equivalent

        // ── Spherical/VR XMP metadata (YouTube VR recognition) ───────────────
        let xmp = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about=""
                xmlns:GSpherical="http://ns.google.com/videos/1.0/spherical/">
              <GSpherical:Spherical>true</GSpherical:Spherical>
              <GSpherical:Stitched>true</GSpherical:Stitched>
              <GSpherical:ProjectionType>equirectangular</GSpherical:ProjectionType>
              <GSpherical:StereoMode>left-right</GSpherical:StereoMode>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        if let xmpData = xmp.data(using: .utf8) {
            let xmpItem = AVMutableMetadataItem()
            xmpItem.keySpace = .quickTimeUserData
            xmpItem.key = "XMP_" as NSString
            xmpItem.value = xmpData as NSData
            writer.metadata = [xmpItem]
        }

        return EncoderSession(
            writer: writer,
            videoInput: videoInput,
            audioInput: audioInput,
            adaptor: adaptor
        )
    }

    func allocatePixelBuffer(from session: EncoderSession) throws -> CVPixelBuffer {
        guard let pool = session.adaptor.pixelBufferPool else {
            throw EncoderError.pixelBufferPoolUnavailable
        }
        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard result == kCVReturnSuccess, let buf = pixelBuffer else {
            throw EncoderError.pixelBufferAllocationFailed(result)
        }
        return buf
    }
}
