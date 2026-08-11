import SwiftUI
import UIKit

struct ProfileAvatarCropView: View {
    let image: UIImage
    let title: String
    let onComplete: (Data?) -> Void

    @State private var controller = ProfileAvatarCropController()
    @State private var isSaving = false
    @State private var saveMessage: String?

    var body: some View {
        GeometryReader { proxy in
            let cropSide = proxy.size.width

            VStack(spacing: 0) {
                header

                ZStack {
                    ProfileAvatarZoomCanvas(image: image, controller: controller)

                    AvatarCropMask()
                        .fill(Color.black.opacity(0.48), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)

                    Circle()
                        .strokeBorder(Color.white.opacity(0.82), lineWidth: 1.5)
                        .allowsHitTesting(false)
                }
                .frame(width: cropSide, height: cropSide)
                .clipped()

                VStack(spacing: 9) {
                    Image(systemName: "hand.pinch")
                        .font(.system(size: 18, weight: .medium))
                    Text("사진을 움직이고 두 손가락으로 확대하세요")
                        .font(.rounded(.subheadline, .medium))

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.rounded(.caption, .medium))
                            .foregroundStyle(.black)
                            .padding(.top, 3)
                    }
                }
                .foregroundStyle(Color.black.opacity(0.58))
                .padding(.top, 24)

                Spacer(minLength: 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.white.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private var header: some View {
        ZStack {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.black)

            HStack {
                circleButton(
                    systemImage: "xmark",
                    foreground: .black,
                    background: Color(white: 0.95),
                    accessibilityLabel: "취소"
                ) {
                    onComplete(nil)
                }

                Spacer()

                circleButton(
                    systemImage: "checkmark",
                    foreground: .white,
                    background: .black,
                    accessibilityLabel: "이 사진 사용",
                    showsProgress: isSaving
                ) {
                    save()
                }
                .disabled(isSaving)
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 92)
        .background(Color.white)
    }

    private func circleButton(
        systemImage: String,
        foreground: Color,
        background: Color,
        accessibilityLabel: String,
        showsProgress: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if showsProgress {
                    ProgressView().tint(foreground)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 23, weight: .semibold))
                }
            }
            .foregroundStyle(foreground)
            .frame(width: 56, height: 56)
            .background(background, in: Circle())
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func save() {
        isSaving = true
        saveMessage = nil

        Task {
            do {
                let result = try controller.visibleSquareJPEGData()
                onComplete(result)
            } catch {
                isSaving = false
                saveMessage = "사진을 저장하지 못했어요. 다시 시도해주세요."
            }
        }
    }
}

private struct AvatarCropMask: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addEllipse(in: rect.insetBy(dx: 1, dy: 1))
        return path
    }
}
