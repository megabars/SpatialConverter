import Foundation

import Foundation
import AppKit

/// Serial actor-based conversion queue. Converts one file at a time.
@MainActor
final class ConversionQueue: ObservableObject {

    @Published private(set) var jobs: [ConversionJob] = []
    @Published private(set) var isRunning: Bool = false

    private let pipeline = ConversionPipeline()
    private var currentTask: Task<Void, Never>?

    // MARK: - Public API

    func add(urls: [URL]) {
        let newJobs = urls
            .filter { url in !jobs.contains(where: { $0.sourceURL == url }) }
            .map { ConversionJob(sourceURL: $0) }
        jobs.append(contentsOf: newJobs)
    }

    func remove(_ job: ConversionJob) {
        guard !job.isActive else { return }
        jobs.removeAll { $0.id == job.id }
    }

    func startAll(settings: ConversionSettings) {
        guard !isRunning else { return }
        isRunning = true
        currentTask = Task { [weak self] in
            await self?.runQueue(settings: settings)
        }
    }

    func clearCompleted() {
        jobs.removeAll { $0.state.isTerminal }
    }

    func cancelAll() {
        currentTask?.cancel()
        currentTask = nil
        for job in jobs where job.isActive {
            job.state = .cancelled
        }
        isRunning = false
    }

    var pendingCount: Int { jobs.filter { $0.state == .pending }.count }
    var completedCount: Int { jobs.filter { $0.state == .completed }.count }
    var hasJobs: Bool { !jobs.isEmpty }
    var allDone: Bool { jobs.allSatisfy { $0.state.isTerminal } }

    // MARK: - Queue loop

    private func runQueue(settings: ConversionSettings) async {
        for job in jobs where job.state == .pending {
            guard !Task.isCancelled else { break }

            await processJob(job, settings: settings)
        }
        await MainActor.run { self.isRunning = false }
    }

    private func processJob(_ job: ConversionJob, settings: ConversionSettings) async {
        await MainActor.run { job.state = .validating }

        do {
            try await pipeline.convert(
                job: job,
                settings: settings,
                progress: { [weak job] p in
                    Task { @MainActor in
                        job?.progress = p
                        if job?.state != .converting {
                            job?.state = .converting
                        }
                    }
                }
            )
            await MainActor.run {
                job.progress = 1.0
                job.state = .completed
                
                // Get output file size
                if let outputURL = job.outputURL,
                   let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
                   let size = attrs[.size] as? Int64 {
                    job.outputFileSize = size
                }
                
                // Show notification if app is in background
                if !NSApplication.shared.isActive {
                    sendNotification(
                        title: "Конвертация завершена",
                        body: "\(job.displayName) → \(job.outputURL?.lastPathComponent ?? "Готово")"
                    )
                }
            }
        } catch ConversionError.cancelled {
            await MainActor.run { job.state = .cancelled }
        } catch {
            await MainActor.run {
                job.state = .failed(error.localizedDescription)
                job.errorMessage = error.localizedDescription
                
                // Show notification for errors
                if !NSApplication.shared.isActive {
                    sendNotification(
                        title: "Ошибка конвертации",
                        body: "\(job.displayName): \(error.localizedDescription)"
                    )
                }
            }
        }
    }
    
    private func sendNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.soundName = NSUserNotificationDefaultSoundName
        NSUserNotificationCenter.default.deliver(notification)
    }
}
