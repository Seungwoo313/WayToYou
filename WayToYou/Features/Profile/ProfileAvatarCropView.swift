import SwiftUI
import UIKit

struct ProfileAvatarCropView: View {
    let image: UIImage
    let onComplete: (Data?) -> Void

    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero
    @State private var isSaving = false
    @State private var saveMessage: String?

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let cropSide = min(proxy.size.width - 32, proxy.size.height * 0.62)
                let imageSize = image.size
                let baseScale = max(cropSide / imageSize.width, cropSide / imageSize.height)
                let renderedSize = CGSize(
                    width: imageSize.width * baseScale * zoom,
                    height: imageSize.height * baseScale * zoom
                )
                let limitedOffset = constrained(offset, renderedSize: renderedSize, cropSide: cropSide)

                VStack(spacing: 24) {
                    Spacer(minLength: 16)

                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: renderedSize.width, height: renderedSize.height)
                            .offset(limitedOffset)

                        AvatarCropMask()
                            .fill(.black.opacity(0.58), style: FillStyle(eoFill: true))

                        Circle()
                            .strokeBorder(.white.opacity(0.95), lineWidth: 2)
                            .padding(1)
                    }
                    .frame(width: cropSide, height: cropSide)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(dragGesture(renderedSize: renderedSize, cropSide: cropSide))
                    .simultaneousGesture(magnificationGesture(imageSize: imageSize, cropSide: cropSide))

                    VStack(spacing: 7) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 15, weight: .semibold))
                        Text("사진을 움직이고 확대해 맞춰주세요")
                            .font(.rounded(.subheadline, .medium))

                        if let saveMessage {
                            Text(saveMessage)
                                .font(.rounded(.caption, .medium))
                                .foregroundStyle(.white)
                        }
                    }
                    .foregroundStyle(.white.opacity(0.72))

                    Spacer(minLength: 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { onComplete(nil) }
                            .foregroundStyle(.white)
                    }
                    ToolbarItem(placement: .principal) {
                        Text("사진 맞추기")
                            .font(.rounded(.headline, .semibold))
                            .foregroundStyle(.white)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            save(
                                cropSide: cropSide,
                                renderedSize: renderedSize,
                                limitedOffset: limitedOffset
                            )
                        } label: {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("사용")
                            }
                        }
                        .font(.rounded(.body, .semibold))
                        .foregroundStyle(.white)
                        .disabled(isSaving)
                    }
                }
                .toolbarBackground(.black, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            }
        }
        .preferredColorScheme(.dark)
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
