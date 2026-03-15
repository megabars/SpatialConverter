import Foundation

enum FFmpegError: Error, LocalizedError {
    case notFound(searchedPaths: [String])
    case nonZeroExit(Int32, stderr: String)
    case interrupted
    case invalidVideoFormat

    var errorDescription: String? {
        switch self {
        case .notFound(let paths):
            return "ffmpeg не найден. Проверьте пути:\n\(paths.joined(separator: "\n"))\n\nУстановите командой: brew install ffmpeg"
        case .nonZeroExit(let code, let stderr):
            let relevantError = extractRelevantError(from: stderr)
            return "ffmpeg завершился с ошибкой (код \(code)):\n\(relevantError)"
        case .interrupted:
            return "Конвертация прервана пользователем"
        case .invalidVideoFormat:
            return "Неверный формат видео. Убедитесь, что это Spatial Video с iPhone 15 Pro или новее"
        }
    }
    
    private func extractRelevantError(from stderr: String) -> String {
        // Extract last few meaningful lines from ffmpeg stderr
        let lines = stderr.components(separatedBy: "\n")
        let errorLines = lines.filter { line in
            line.contains("Error") || 
            line.contains("Invalid") || 
            line.contains("failed") ||
            line.contains("not found")
        }
        if !errorLines.isEmpty {
            return errorLines.suffix(3).joined(separator: "\n")
        }
        return String(stderr.suffix(300))
    }
}

actor FFmpegFallback {

    private static let searchPaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]

    func findFFmpeg() -> String? {
        Self.searchPaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    func convert(
        sourceURL: URL,
        outputURL: URL,
        settings: ConversionSettings,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        guard let ffmpegPath = findFFmpeg() else {
            throw FFmpegError.notFound(searchedPaths: Self.searchPaths)
        }

        let duration = try await getVideoDuration(url: sourceURL)

        // Build arguments — exact same approach confirmed working in convert_to_sbs.sh
        let codec = settings.videoCodec == .h264 ? "libx264" : "libx265"
        let filterGraph = [
            "[0:v]split[a][b]",
            "[a]select='not(mod(n\\,2))',setpts=N/FRAME_RATE/TB[right]",
            "[b]select='mod(n\\,2)',setpts=N/FRAME_RATE/TB[left]",
            "[left][right]hstack[v]"
        ].joined(separator: ";")

        var args: [String] = [
            "-y",
            "-view_ids", "-1",
            "-i", sourceURL.path,
            "-filter_complex", filterGraph,
            "-map", "[v]",
            "-map", "0:1",
            "-c:v", codec,
            "-crf", settings.qualityPreset.ffmpegCRF,
            "-preset", "slow",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "192k",
            "-movflags", "+faststart",
            outputURL.path
        ]
        _ = args // suppress warning

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = args

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        try process.run()

        // Parse progress from ffmpeg stderr lines
        var stderrText = ""
        let handle = stderrPipe.fileHandleForReading

        for try await line in handle.bytes.lines {
            try Task.checkCancellation()
            stderrText += line + "\n"
            if duration > 0, let t = parseTime(from: line) {
                progress(min(t / duration, 0.99))
            }
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw FFmpegError.nonZeroExit(process.terminationStatus, stderr: stderrText)
        }
        progress(1.0)
    }

    // MARK: - Helpers

    private func getVideoDuration(url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    private func parseTime(from line: String) -> Double? {
        // Matches "time=HH:MM:SS.ss" in ffmpeg progress output
        guard let range = line.range(
            of: #"time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})"#,
            options: .regularExpression
        ) else { return nil }

        let timeStr = String(line[range].dropFirst(5)) // drop "time="
        let parts = timeStr.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + s
    }
}

// Keep AVFoundation import local to this helper
import AVFoundation
import CoreMedia
