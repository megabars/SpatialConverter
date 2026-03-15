import Foundation
import AVFoundation
import CoreMedia

struct SpatialVideoInfo: Sendable {
    let sourceURL: URL
    let duration: CMTime
    let nominalFrameRate: Float
    let naturalSize: CGSize
    let totalFrames: Int
    let audioTrackIndex: Int?
    let hasMultipleAudioTracks: Bool
}
