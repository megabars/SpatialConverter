import Foundation
import AVFoundation
import AppKit

@Observable
final class ConversionJob: Identifiable, @unchecked Sendable {
    let id: UUID
    let sourceURL: URL
    var outputURL: URL?
    var state: JobState
    var progress: Double
    var errorMessage: String?
    var sourceInfo: SpatialVideoInfo?
    var usedFallback: Bool
    var outputFileSize: Int64?
    var conversionMethod: String? // "AVFoundation" или "ffmpeg"

    enum JobState: Equatable {
        case pending
        case validating
        case converting
        case completed
        case failed(String)
        case cancelled

        var isTerminal: Bool {
            switch self {
            case .completed, .failed, .cancelled: return true
            default: return false
            }
        }

        static func == (lhs: JobState, rhs: JobState) -> Bool {
            switch (lhs, rhs) {
            case (.pending, .pending),
                 (.validating, .validating),
                 (.converting, .converting),
                 (.completed, .completed),
                 (.cancelled, .cancelled): return true
            case (.failed(let a), .failed(let b)): return a == b
            default: return false
            }
        }
    }

    init(sourceURL: URL) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.state = .pending
        self.progress = 0
        self.usedFallback = false
        self.outputFileSize = nil
        self.conversionMethod = nil
    }

    var displayName: String { sourceURL.lastPathComponent }

    var isActive: Bool { state == .converting || state == .validating }
    
    var outputFileSizeFormatted: String? {
        guard let size = outputFileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
    
    func revealInFinder() {
        guard let url = outputURL else { return }
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }
}
