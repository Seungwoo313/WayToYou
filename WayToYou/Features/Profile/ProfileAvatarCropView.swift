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
            let topInset = proxy.safeAreaInsets.top
            let bottomInset = proxy.safeAreaInsets.bottom
            let headerHeight: CGFloat = 82
            let availableHeight = proxy.size.height
                - topInset
                - bottomInset
                - headerHeight
                - 32
            let cropSide = max(min(proxy.size.width, availableHeight), 160)

            ZStack {
                Color.black.ignoresSafeArea()

                Color.white
                    .frame(height: topInset + headerHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea(edges: .top)

                VStack(spacing: 0) {
                    header
                        .frame(height: headerHeight)

                    Spacer(minLength: 16)

                    cropCanvas(size: cropSide)

                    Spacer(minLength: 16)
                }
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let saveMessage {
                    Text(saveMessage)
                        .font(.rounded(.caption, .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .padding(.horizontal, 24)
                        .padding(.bottom, bottomInset + 20)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func cropCanvas(size: CGFloat) -> some View {
        ZStack {
            ProfileAvatarZoomCanvas(image: image, controller: controller)

            AvatarCropMask()
                .fill(Color.black.opacity(0.48), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

            Circle()
                .strokeBorder(Color.white.opacity(0.82), lineWidth: 1.5)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private var header: some View {
        ZStack {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 88)

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
