import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

enum ConversionError: Error, LocalizedError {
    case validationFailed(String)
    case insufficientDiskSpace(needed: Int64, available: Int64)
    case avFoundationFailed(Error)
    case ffmpegFailed(Error)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .validationFailed(let msg):     return msg
        case .avFoundationFailed(let e):     return "AVFoundation: \(e.localizedDescription)"
        case .ffmpegFailed(let e):           return "ffmpeg: \(e.localizedDescription)"
        case .cancelled:                     return "Отменено"
        case .insufficientDiskSpace(let need, let avail):
            let fmt = ByteCountFormatter()
            fmt.allowedUnits = [.useGB, .useMB]
            fmt.countStyle = .file
            return "Недостаточно места: нужно \(fmt.string(fromByteCount: need)), доступно \(fmt.string(fromByteCount: avail))"
        }
    }

    var isFallbackEligible: Bool {
        if case .avFoundationFailed = self { return true }
        return false
    }
}

actor ConversionPipeline {

    private let decoder    = SpatialVideoDecoder()
    private let compositor = SBSCompositor()
    private let encoder    = SBSEncoder()
    private let fallback   = FFmpegFallback()

    func convert(
        job: ConversionJob,
        settings: ConversionSettings,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        try Task.checkCancellation()

        // 1. Validate
        let info = try await SpatialVideoValidator.validate(url: job.sourceURL)
        await MainActor.run { job.sourceInfo = info }

        // 2. Determine output URL
        let outputURL = settings.outputURL(for: job.sourceURL)
        await MainActor.run { job.outputURL = outputURL }

        // 3. Check disk space (rough estimate: source file size × 1.5)
        try checkDiskSpace(outputURL: outputURL, sourceURL: job.sourceURL)

        // 4. Try AVFoundation path, fall back to ffmpeg
        do {
            await MainActor.run { job.conversionMethod = "AVFoundation" }
            try await convertViaAVFoundation(
                info: info, outputURL: outputURL,
                settings: settings, progress: progress
            )
        } catch DecoderError.rightViewNotFound {
            // AVFoundation couldn't extract dual views → fall back silently
            await MainActor.run { 
                job.usedFallback = true
                job.conversionMethod = "ffmpeg"
            }
            try await convertViaFFmpeg(
                info: info, outputURL: outputURL,
                settings: settings, progress: progress
            )
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: outputURL)
            throw ConversionError.cancelled
        } catch {
            // Other AVFoundation errors → also try ffmpeg
            await MainActor.run { 
                job.usedFallback = true
                job.conversionMethod = "ffmpeg"
            }
            try await convertViaFFmpeg(
                info: info, outputURL: outputURL,
                settings: settings, progress: progress
            )
        }
    }

    // MARK: - AVFoundation path

    private func convertViaAVFoundation(
        info: SpatialVideoInfo,
        outputURL: URL,
        settings: ConversionSettings,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {

        let asset = AVURLAsset(url: info.sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = tracks.first else {
            throw DecoderError.setupFailed("No video track")
        }

        let session = try await encoder.makeSession(
            outputURL: outputURL, settings: settings, info: info
        )

        session.writer.startWriting()
        session.writer.startSession(atSourceTime: .zero)

        // Audio copy (concurrent task)
        let audioTask = Task {
            if let audioInput = session.audioInput,
               let audioIdx = info.audioTrackIndex {
                try await copyAudio(
                    asset: asset, trackIndex: audioIdx,
                    into: audioInput
                )
            }
        }

        // Video frame loop — pull-based: decoder yields one frame at a time,
        // so the encoder's backpressure naturally throttles decoding (no dropped frames).
        try await decoder.setup(asset: asset, videoTrack: videoTrack)
        var frameIndex = 0
        var framesWritten = 0
        let total = max(info.totalFrames, 1)

        do {
            while let pair = try await decoder.nextFrame(index: frameIndex) {
                try Task.checkCancellation()

                let pixelBuffer = try await encoder.allocatePixelBuffer(from: session)
                compositor.composeAndRender(left: pair.left, right: pair.right, into: pixelBuffer)

                // Backpressure: wait until encoder is ready
                while !session.videoInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 5_000_000)
                    try Task.checkCancellation()
                }

                session.adaptor.append(pixelBuffer, withPresentationTime: pair.presentationTime)
                frameIndex += 1
                framesWritten += 1
                progress(Double(framesWritten) / Double(total))
            }
        } catch {
            await decoder.teardown()
            throw error
        }
        await decoder.teardown()

        // Finish
        session.videoInput.markAsFinished()
        try await audioTask.value
        session.audioInput?.markAsFinished()

        await session.writer.finishWriting()

        if session.writer.status == .failed {
            throw EncoderError.encodingFailed(session.writer.error)
        }
    }

    // MARK: - Audio copy helper

    private func copyAudio(
        asset: AVURLAsset,
        trackIndex: Int,
        into audioInput: AVAssetWriterInput
    ) async throws {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard trackIndex < tracks.count else { return }
        let track = tracks[trackIndex]

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil) // passthrough
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return }
        reader.add(output)
        reader.startReading()

        while reader.status == .reading {
            guard let sample = output.copyNextSampleBuffer() else { break }
            while !audioInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            audioInput.append(sample)
        }
    }

    // MARK: - ffmpeg path

    private func convertViaFFmpeg(
        info: SpatialVideoInfo,
        outputURL: URL,
        settings: ConversionSettings,
        progress: @Sendable @escaping (Double) -> Void
    ) async throws {
        do {
            try await fallback.convert(
                sourceURL: info.sourceURL,
                outputURL: outputURL,
                settings: settings,
                progress: progress
            )
        } catch {
            throw ConversionError.ffmpegFailed(error)
        }
    }

    // MARK: - Disk space check

    private func checkDiskSpace(outputURL: URL, sourceURL: URL) throws {
        let folder = outputURL.deletingLastPathComponent()
        guard let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else { return }

        let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path)
        let sourceSize = attrs?[.size] as? Int64 ?? 0
        let needed = Int64(Double(sourceSize) * 1.5)

        if available < needed {
            throw ConversionError.insufficientDiskSpace(needed: needed, available: available)
        }
    }
}
