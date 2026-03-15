import SwiftUI

struct FileRowView: View {
    @Bindable var job: ConversionJob
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            // Name + status
            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Right side indicator
            Group {
                switch job.state {
                case .converting:
                    ProgressRingView(progress: job.progress)
                        .frame(width: 32, height: 32)

                case .completed:
                    HStack(spacing: 4) {
                        if job.usedFallback {
                            Text("ffmpeg")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                        } else {
                            Text("AVFoundation")
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.8), in: RoundedRectangle(cornerRadius: 3))
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }

                case .failed(let msg):
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .help(msg)

                case .pending:
                    Text("Ожидание")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                case .validating:
                    ProgressView()
                        .controlSize(.small)

                case .cancelled:
                    Image(systemName: "minus.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // Double-click to reveal in Finder
            if case .completed = job.state {
                job.revealInFinder()
            }
        }
        .contextMenu {
            if case .completed = job.state {
                Button("Показать в Finder") {
                    job.revealInFinder()
                }
                Divider()
            }
            if case .failed = job.state {
                Button("Копировать ошибку") {
                    if let error = job.errorMessage {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(error, forType: .string)
                    }
                }
                Divider()
            }
            if !job.isActive {
                Button("Удалить из списка", role: .destructive) {
                    onDelete()
                }
            }
        }
    }

    private var iconName: String {
        switch job.state {
        case .pending:    return "video.fill"
        case .validating: return "magnifyingglass"
        case .converting: return "arrow.triangle.2.circlepath"
        case .completed:  return "video.fill.badge.checkmark"
        case .failed:     return "video.fill.badge.exclamationmark"
        case .cancelled:  return "video.slash.fill"
        }
    }

    private var iconColor: Color {
        switch job.state {
        case .pending:    return .secondary
        case .validating: return .blue
        case .converting: return .blue
        case .completed:  return .green
        case .failed:     return .red
        case .cancelled:  return .secondary
        }
    }

    private var statusText: String {
        switch job.state {
        case .pending:             return "Готово к конвертации"
        case .validating:          return "Проверка файла…"
        case .converting:          
            let method = job.conversionMethod ?? "AVFoundation"
            return "Конвертация \(Int(job.progress * 100))% • \(method)"
        case .completed:
            if let size = job.outputFileSizeFormatted {
                return "\(job.outputURL?.lastPathComponent ?? "Готово") • \(size)"
            } else if let output = job.outputURL {
                return output.lastPathComponent
            }
            return "Готово"
        case .failed(let msg):     return msg
        case .cancelled:           return "Отменено"
        }
    }
}
