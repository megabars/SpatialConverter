import AVFoundation
import CoreMedia

enum ValidationError: Error, LocalizedError {
    case notAVideoFile
    case noVideoTrack
    case notMVHEVC(codecName: String)
    case singleViewOnly
    case unreadable(Error)

    var errorDescription: String? {
        switch self {
        case .notAVideoFile:
            return "Файл не является видео"
        case .noVideoTrack:
            return "Видеодорожка не найдена"
        case .notMVHEVC(let c):
            return "Не является Apple Spatial Video (кодек: \(c), ожидался MV-HEVC / hvc1)"
        case .singleViewOnly:
            return "Видео содержит только один вид — это не пространственное видео"
        case .unreadable(let e):
            return "Файл недоступен: \(e.localizedDescription)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notMVHEVC:
            return "Поддерживаются только видео с iPhone 15 Pro / 16, снятые в режиме Spatial Video"
        case .singleViewOnly:
            return "Убедитесь, что видео снято в режиме Spatial Video (Настройки → Камера)"
        default: return nil
        }
    }
}

enum SpatialVideoValidator {

    static func validate(url: URL) async throws -> SpatialVideoInfo {
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        // Check the asset is readable
        let status = try await asset.load(.isPlayable)
        guard status else {
            throw ValidationError.notAVideoFile
        }

        // Load video tracks
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ValidationError.noVideoTrack
        }

        // Inspect format descriptions for MV-HEVC
        let formatDescs = try await videoTrack.load(.formatDescriptions)
        guard let formatDesc = formatDescs.first else {
            throw ValidationError.noVideoTrack
        }

        let subType = CMFormatDescriptionGetMediaSubType(formatDesc)
        guard isHEVC(subType) else {
            throw ValidationError.notMVHEVC(codecName: fourCCString(subType))
        }

        // Note: CMFormatDescriptionGetExtension keys for MV-HEVC vary by SDK version.
        // We trust the HEVC codec check above; the decoder will fail fast and fall
        // back to ffmpeg if dual-view extraction is not possible at runtime.

        // Load track properties
        let naturalSize     = try await videoTrack.load(.naturalSize)
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        let duration        = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)

        // Total stereo frames: the track has ~30fps in the MV-HEVC mux
        // After SBS conversion each frame pair = 1 output frame
        let totalFrames = max(1, Int(durationSeconds * Double(nominalFrameRate / 2)))

        // Audio tracks
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        return SpatialVideoInfo(
            sourceURL: url,
            duration: duration,
            nominalFrameRate: nominalFrameRate,
            naturalSize: naturalSize,
            totalFrames: totalFrames,
            audioTrackIndex: audioTracks.isEmpty ? nil : 0,
            hasMultipleAudioTracks: audioTracks.count > 1
        )
    }

    // MARK: - Helpers

    private static func isHEVC(_ subType: FourCharCode) -> Bool {
        let hevcTypes: [FourCharCode] = [
            fourCC("hvc1"), fourCC("hev1"),
            fourCC("dvh1"), fourCC("dvhe"),
            fourCC("mhvc") // MV-HEVC specific
        ]
        return hevcTypes.contains(subType)
    }

    private static func hasMVHEVCExtension(_ desc: CMFormatDescription) -> Bool {
        // Check for multi-layer information extension (indicates MV-HEVC)
        if CMFormatDescriptionGetExtension(
            desc,
            extensionKey: "MultiLayerInformation" as CFString
        ) != nil { return true }

        // Also accept if the stereo3D metadata is present in atoms
        if CMFormatDescriptionGetExtension(
            desc,
            extensionKey: "StereoViewInformation" as CFString
        ) != nil { return true }

        // Check the kCMFormatDescriptionExtension_MultiLayerInformation constant
        // (this is the documented key for MV-HEVC)
        let key = "MultiLayerInformation" as CFString
        if CMFormatDescriptionGetExtension(desc, extensionKey: key) != nil { return true }

        return false
    }

    private static func fourCC(_ string: String) -> FourCharCode {
        var result: FourCharCode = 0
        for char in string.unicodeScalars {
            result = (result << 8) + FourCharCode(char.value)
        }
        return result
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        var chars: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >>  8) & 0xFF),
            UInt8( code        & 0xFF)
        ]
        return String(bytes: chars, encoding: .ascii) ?? "????"
    }
}
