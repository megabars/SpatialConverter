import SwiftUI

struct ContentView: View {
    @StateObject private var queue = ConversionQueue()
    @State private var settings = ConversionSettings()

    var body: some View {
        HSplitView {
            // ── Left: file list or drop zone ─────────────────────────────────
            VStack(spacing: 0) {
                if queue.hasJobs {
                    fileListView
                } else {
                    DropZoneView { urls in queue.add(urls: urls) }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()
                bottomToolbar
            }
            .frame(minWidth: 420)

            // ── Right: settings ───────────────────────────────────────────────
            SettingsPanel(settings: $settings)
                .frame(width: 270)
        }
        .frame(minWidth: 720, minHeight: 480)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AddFilesToQueue"))) { notification in
            if let urls = notification.userInfo?["urls"] as? [URL] {
                queue.add(urls: urls)
            }
        }
    }

    // MARK: - File List

    private var fileListView: some View {
        VStack(spacing: 0) {
            // Header with "Add more" button
            HStack {
                Text("Файлы")
                    .font(.headline)
                Spacer()
                Button {
                    addMoreFiles()
                } label: {
                    Label("Добавить ещё", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .disabled(queue.isRunning)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(queue.jobs) { job in
                        FileRowView(job: job, onDelete: {
                            queue.remove(job)
                        })
                        .padding(.horizontal, 16)
                        if job.id != queue.jobs.last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .onDrop(of: [.movie, .mpeg4Movie, .quickTimeMovie], isTargeted: nil) { providers in
            // Allow continuing to drop files when list is visible
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadItem(forTypeIdentifier: "public.movie") as? URL {
                        urls.append(url)
                    }
                }
                if !urls.isEmpty { queue.add(urls: urls) }
            }
            return true
        }
    }

    private func addMoreFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Добавить"
        if panel.runModal() == .OK {
            queue.add(urls: panel.urls)
        }
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack(spacing: 12) {
            // Status summary
            if queue.hasJobs {
                Text(statusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Clear completed
            if queue.jobs.contains(where: { $0.state.isTerminal }) && !queue.isRunning {
                Button("Очистить") {
                    queue.clearCompleted()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            // Cancel / Convert
            if queue.isRunning {
                Button(role: .destructive, action: { queue.cancelAll() }) {
                    Label("Остановить", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button(action: { queue.startAll(settings: settings) }) {
                    Label("Конвертировать", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!queue.hasJobs || queue.pendingCount == 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusSummary: String {
        let total = queue.jobs.count
        let done  = queue.completedCount
        let pend  = queue.pendingCount
        if queue.isRunning {
            return "Конвертация… (\(done)/\(total))"
        } else if done == total && total > 0 {
            return "Готово: \(total) файл(ов)"
        } else {
            return "Файлов: \(total), ожидает: \(pend)"
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 720, height: 520)
}
