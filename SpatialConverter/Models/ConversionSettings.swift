import Foundation
import AVFoundation

struct ConversionSettings: Sendable {
    var videoCodec: VideoCodec = .h264
    var qualityPreset: QualityPreset = .balanced
    var useSourceFolder: Bool = true
    var customOutputFolder: URL? = nil
    var audioPassthrough: Bool = true

    enum VideoCodec: String, CaseIterable, Sendable {
        case h264 = "H.264"
        case h265 = "H.265"

        var avCodecType: AVVideoCodecType {
            switch self {
            case .h264: return .h264
            case .h265: return .hevc
            }
        }
    }

    enum QualityPreset: String, CaseIterable, Sendable {
        case high = "Высокое"
        case balanced = "Среднее"
        case small = "Компактное"

        var h264Bitrate: Int {
            switch self {
            case .high:     return 35_000_000
            case .balanced: return 20_000_000
            case .small:    return 10_000_000
            }
        }

        var h265Bitrate: Int {
            switch self {
            case .high:     return 20_000_000
            case .balanced: return 12_000_000
            case .small:    return  6_000_000
            }
        }

        var ffmpegCRF: String {
            switch self {
            case .high:     return "18"
            case .balanced: return "23"
            case .small:    return "28"
            }
        }

        func bitrate(for codec: VideoCodec) -> Int {
            codec == .h264 ? h264Bitrate : h265Bitrate
        }
    }

    func outputURL(for sourceURL: URL) -> URL {
        let base = useSourceFolder ? sourceURL.deletingLastPathComponent()
                                   : (customOutputFolder ?? sourceURL.deletingLastPathComponent())
        let name = sourceURL.deletingPathExtension().lastPathComponent
        return base.appendingPathComponent("\(name)_SBS_LR.mp4")
    }
}
