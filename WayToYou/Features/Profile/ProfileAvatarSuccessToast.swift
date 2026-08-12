import SwiftUI
import UIKit

struct ProfileAvatarSuccessToast: View {
    let message: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var circleIsExpanded = false
    @State private var checkProgress: CGFloat = 0

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemGreen))
                    .frame(
                        width: circleIsExpanded ? 24 : 8,
                        height: circleIsExpanded ? 24 : 8
                    )

                ToastCheckmark()
                    .trim(from: 0, to: checkProgress)
                    .stroke(
                        Color.white,
                        style: StrokeStyle(
                            lineWidth: 2.4,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .frame(width: 12, height: 9)
            }
            .frame(width: 24, height: 24)

            Text(message)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.88)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Color.white, in: Capsule())
        .shadow(color: .black.opacity(0.22), radius: 12, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
        .allowsHitTesting(false)
        .task { await animateIcon() }
    }

    @MainActor
    private func animateIcon() async {
        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()

        if reduceMotion {
            circleIsExpanded = true
            checkProgress = 1
            feedback.notificationOccurred(.success)
            return
        }

        do {
            try await Task.sleep(for: .milliseconds(120))
        } catch {
            return
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.56)) {
            circleIsExpanded = true
        }

        do {
            try await Task.sleep(for: .milliseconds(150))
        } catch {
            return
        }

        feedback.notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.22)) {
            checkProgress = 1
        }
    }
}

private struct ToastCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
