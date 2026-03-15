import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    var onDrop: ([URL]) -> Void
    @State private var isTargeted = false

    private let acceptedTypes: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie,
                                            UTType("public.hevc") ?? .movie]

    private var borderColor: Color {
        isTargeted ? .blue : Color.secondary.opacity(0.4)
    }
    private var fillColor: Color {
        isTargeted ? Color.blue.opacity(0.06) : Color.clear
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    borderColor,
                    style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [] : [8, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(fillColor)
                )
                .animation(.easeInOut(duration: 0.15), value: isTargeted)

            VStack(spacing: 14) {
                Image(systemName: "video.badge.plus")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundStyle(isTargeted ? .blue : .secondary)

                VStack(spacing: 4) {
                    Text("Перетащите Spatial Video сюда")
                        .font(.title3.weight(.medium))
                    Text("или нажмите для выбора файлов")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(".MOV / .MP4 с iPhone 15 Pro и новее")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(32)
        }
        .contentShape(Rectangle())
        .onTapGesture { openFilePicker() }
        .onDrop(of: acceptedTypes, isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }

    // MARK: - Handlers

    private func handleDrop(providers: [NSItemProvider]) {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let url = item as? URL { urls.append(url) }
                else if let data = item as? Data,
                        let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty { onDrop(urls) }
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.prompt = "Выбрать"
        panel.title = "Выберите Spatial Video файлы"

        if panel.runModal() == .OK {
            onDrop(panel.urls)
        }
    }
}
