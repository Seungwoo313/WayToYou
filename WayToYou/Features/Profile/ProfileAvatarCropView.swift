import SwiftUI
import UIKit

struct ProfileAvatarCropView: View {
    let image: UIImage
    let onComplete: (Data?) -> Void
    let onChooseAnother: () -> Void

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero
    @State private var isSaving = false
    @State private var saveMessage: String?

    var body: some View {
        GeometryReader { proxy in
            let cropSide = proxy.size.width
            let imageSize = image.size
            let baseScale = max(cropSide / imageSize.width, cropSide / imageSize.height)
            let renderedSize = CGSize(
                width: imageSize.width * baseScale * zoom,
                height: imageSize.height * baseScale * zoom
            )
            let limitedOffset = constrained(offset, renderedSize: renderedSize, cropSide: cropSide)

            VStack(spacing: 0) {
                header(
                    cropSide: cropSide,
                    renderedSize: renderedSize,
                    limitedOffset: limitedOffset
                )

                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: renderedSize.width, height: renderedSize.height)
                        .offset(limitedOffset)

                    AvatarCropMask()
                        .fill(.black.opacity(0.48), style: FillStyle(eoFill: true))

                    Circle()
                        .strokeBorder(.white.opacity(0.9), lineWidth: 1.5)
                }
                .frame(width: cropSide, height: cropSide)
                .clipped()
                .contentShape(Rectangle())
                .gesture(dragGesture(renderedSize: renderedSize, cropSide: cropSide))
                .simultaneousGesture(magnificationGesture(imageSize: imageSize, cropSide: cropSide))

                cropControls

                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.ignoresSafeArea())
        }
        .preferredColorScheme(.light)
    }

    private func header(
        cropSide: CGFloat,
        renderedSize: CGSize,
        limitedOffset: CGSize
    ) -> some View {
        ZStack {
            Text("프로필 사진 편집")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.black)

            HStack {
                Button {
                    onComplete(nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Color(white: 0.94), in: Circle())
                }
                .accessibilityLabel("취소")

                Spacer()

                Button {
                    save(
                        cropSide: cropSide,
                        renderedSize: renderedSize,
                        limitedOffset: limitedOffset
                    )
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 23, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Color.black, in: Circle())
                }
                .disabled(isSaving)
                .accessibilityLabel("이 사진 사용")
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 92)
        .background(Color.white)
    }

    private var cropControls: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "minus.magnifyingglass")
                Slider(
                    value: Binding(
                        get: { zoom },
                        set: { value in
                            zoom = value
                            settledZoom = value
                        }
                    ),
                    in: 1...5
                )
                    .tint(.black)
                Image(systemName: "plus.magnifyingglass")
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.black)

            Text("사진을 움직이거나 두 손가락으로 확대하세요")
                .font(.rounded(.subheadline, .medium))
                .foregroundStyle(Color.black.opacity(0.58))

            if let saveMessage {
                Text(saveMessage)
                    .font(.rounded(.caption, .medium))
                    .foregroundStyle(.black)
            }

            Button(action: onChooseAnother) {
                Label("다른 사진 고르기", systemImage: "photo.on.rectangle")
                    .font(.rounded(.subheadline, .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Color(white: 0.94), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    private func dragGesture(renderedSize: CGSize, cropSide: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                offset = constrained(
                    CGSize(
                        width: settledOffset.width + value.translation.width,
                        height: settledOffset.height + value.translation.height
                    ),
                    renderedSize: renderedSize,
                    cropSide: cropSide
                )
            }
            .onEnded { _ in
                settledOffset = constrained(offset, renderedSize: renderedSize, cropSide: cropSide)
                offset = settledOffset
            }
    }

    private func magnificationGesture(imageSize: CGSize, cropSide: CGFloat) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(max(settledZoom * value, 1), 5)
                let nextBaseScale = max(cropSide / imageSize.width, cropSide / imageSize.height)
                let nextSize = CGSize(
                    width: imageSize.width * nextBaseScale * zoom,
                    height: imageSize.height * nextBaseScale * zoom
                )
                offset = constrained(offset, renderedSize: nextSize, cropSide: cropSide)
            }
            .onEnded { _ in
                settledZoom = zoom
                settledOffset = offset
            }
    }

    private func constrained(_ proposed: CGSize, renderedSize: CGSize, cropSide: CGFloat) -> CGSize {
        let maximumX = max((renderedSize.width - cropSide) / 2, 0)
        let maximumY = max((renderedSize.height - cropSide) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -maximumX), maximumX),
            height: min(max(proposed.height, -maximumY), maximumY)
        )
    }

    private func save(
        cropSide: CGFloat,
        renderedSize: CGSize,
        limitedOffset: CGSize
    ) {
        isSaving = true
        saveMessage = nil

        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let outputPixels: CGFloat = 512
                    let outputScale = outputPixels / cropSide
                    let origin = CGPoint(
                        x: (cropSide - renderedSize.width) / 2 + limitedOffset.width,
                        y: (cropSide - renderedSize.height) / 2 + limitedOffset.height
                    )
                    let format = UIGraphicsImageRendererFormat.default()
                    format.scale = 1
                    format.opaque = true
                    let rendered = UIGraphicsImageRenderer(
                        size: CGSize(width: outputPixels, height: outputPixels),
                        format: format
                    ).image { context in
                        UIColor.black.setFill()
                        context.fill(CGRect(x: 0, y: 0, width: outputPixels, height: outputPixels))
                        image.draw(
                            in: CGRect(
                                x: origin.x * outputScale,
                                y: origin.y * outputScale,
                                width: renderedSize.width * outputScale,
                                height: renderedSize.height * outputScale
                            )
                        )
                    }
                    guard let jpeg = rendered.jpegData(compressionQuality: 0.9) else {
                        throw ProfileAvatarProcessingError.encodingFailed
                    }
                    return try ProfileAvatarProcessor.jpegData(from: jpeg)
                }.value
                onComplete(data)
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
