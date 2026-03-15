import SwiftUI

struct ProgressRingView: View {
    let progress: Double  // 0.0 – 1.0
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, style: StrokeStyle(
                    lineWidth: lineWidth, lineCap: .round
                ))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)

            Text("\(Int(progress * 100))%")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
