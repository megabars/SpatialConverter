import SwiftUI

struct SettingsPanel: View {
    @Binding var settings: ConversionSettings

    var body: some View {
        Form {
            // ── Output folder ────────────────────────────────────────────────
            Section("Выходная папка") {
                Toggle("Рядом с исходным файлом", isOn: $settings.useSourceFolder)

                if !settings.useSourceFolder {
                    HStack {
                        Text(settings.customOutputFolder?.lastPathComponent ?? "Не выбрана")
                            .foregroundStyle(settings.customOutputFolder == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Выбрать…") { chooseFolder() }
                            .buttonStyle(.link)
                    }
                }
            }

            // ── Video codec ──────────────────────────────────────────────────
            Section("Видеокодек") {
                Picker("Кодек", selection: $settings.videoCodec) {
                    ForEach(ConversionSettings.VideoCodec.allCases, id: \.self) { codec in
                        Text(codecLabel(codec)).tag(codec)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            // ── Quality ──────────────────────────────────────────────────────
            Section("Качество") {
                Picker("", selection: $settings.qualityPreset) {
                    ForEach(ConversionSettings.QualityPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(qualityDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Audio ────────────────────────────────────────────────────────
            Section("Аудио") {
                Toggle("Копировать оригинальное аудио", isOn: $settings.audioPassthrough)
                if settings.audioPassthrough {
                    Text("AAC-дорожка будет скопирована без перекодирования")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // ── Output info ──────────────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Формат: Full SBS 3840×1080", systemImage: "viewfinder.rectangular")
                        .help("Side-by-Side формат с полным разрешением каждого глаза")
                    Label("Имя: {оригинал}_SBS_LR.mp4", systemImage: "doc.text")
                        .help("Автоматическое именование для DeoVR")
                    Label("DeoVR: авто-определение", systemImage: "checkmark.circle")
                        .help("Суффикс _LR распознаётся большинством VR-плееров")
                    if hasFFmpeg() {
                        Label("ffmpeg: установлен ✓", systemImage: "terminal")
                            .foregroundStyle(.green)
                            .help("Резервный путь декодирования доступен")
                    } else {
                        Label("ffmpeg: не найден", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .help("Рекомендуется установить: brew install ffmpeg")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Информация")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func hasFFmpeg() -> Bool {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        return paths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    private func codecLabel(_ codec: ConversionSettings.VideoCodec) -> String {
        switch codec {
        case .h264: return "H.264 — широкая совместимость"
        case .h265: return "H.265 — меньший размер файла"
        }
    }

    private var qualityDescription: String {
        let bitrate: Int
        switch settings.qualityPreset {
        case .high:     bitrate = settings.videoCodec == .h264 ? 35 : 20
        case .balanced: bitrate = settings.videoCodec == .h264 ? 20 : 12
        case .small:    bitrate = settings.videoCodec == .h264 ? 10 : 6
        }
        return "≈ \(bitrate) Мбит/с · CRF \(settings.qualityPreset.ffmpegCRF)"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать папку"
        if panel.runModal() == .OK, let url = panel.url {
            settings.customOutputFolder = url
        }
    }
}
