import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UIKit

struct ProfileAvatarPicker: View {
    let data: Data?
    let hasAvatar: Bool
    let displayName: String
    let isWorking: Bool
    var size: CGFloat = 76
    let onImageReady: (Data) -> Void
    let onUseDefault: () -> Void
    let onError: (String) -> Void

    @State private var isChoosingSource = false
    @State private var isShowingLibrary = false
    @State private var isShowingCamera = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var cropRequest: AvatarCropRequest?
    @State private var isLoadingSource = false

    var body: some View {
        Button {
            isChoosingSource = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatarImage(data: data, displayName: displayName, size: size)

                Image(systemName: hasAvatar ? "pencil" : "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 23, height: 23)
                    .background(Color.black, in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1) }
            }
            .overlay {
                if isWorking || isLoadingSource {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: size, height: size)
                        .overlay { ProgressView().tint(.white) }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking || isLoadingSource)
        .accessibilityLabel(hasAvatar ? "프로필 사진 변경" : "프로필 사진 추가")
        .accessibilityHint("촬영하거나 앨범에서 사진을 선택합니다")
        .confirmationDialog("프로필 사진", isPresented: $isChoosingSource) {
            Button("카메라로 촬영") {
                let authorization = AVCaptureDevice.authorizationStatus(for: .video)
                if authorization == .denied || authorization == .restricted {
                    onError("설정에서 카메라 접근을 허용해주세요.")
                } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    isShowingCamera = true
                } else {
                    onError("이 기기에서는 카메라를 사용할 수 없어요.")
                }
            }
            Button("앨범에서 선택") { isShowingLibrary = true }
            if hasAvatar {
                Button("기본 이미지로 변경", role: .destructive) { onUseDefault() }
            }
            Button("취소", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $isShowingLibrary,
            selection: $selectedItem,
            matching: .images
        )
        .onChange(of: selectedItem) { _, item in
            Task { await loadLibraryImage(from: item) }
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            ProfileCameraPicker(
                onCapture: { image in
                    isShowingCamera = false
                    presentCropAfterCameraDismisses(image.preparedForAvatarCrop)
                },
                onCancel: { isShowingCamera = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $cropRequest) { request in
            ProfileAvatarCropView(
                image: request.image,
                onComplete: { result in
                    cropRequest = nil
                    guard let result else { return }
                    onImageReady(result)
                },
                onChooseAnother: {
                    cropRequest = nil
                    presentSourceMenuAfterCropDismisses()
                }
            )
        }
    }

    private func loadLibraryImage(from item: PhotosPickerItem?) async {
        guard let item else { return }

        isLoadingSource = true
        defer {
            isLoadingSource = false
            selectedItem = nil
        }

        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                throw ProfileAvatarProcessingError.invalidImage
            }
            let image = try await Task.detached(priority: .userInitiated) {
                guard let image = AvatarCropImageLoader.image(from: sourceData) else {
                    throw ProfileAvatarProcessingError.invalidImage
                }
                return image
            }.value
            cropRequest = AvatarCropRequest(image: image)
        } catch {
            onError("사진을 불러오지 못했어요. 다른 사진을 선택해주세요.")
        }
    }

    private func presentCropAfterCameraDismisses(_ image: UIImage) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            cropRequest = AvatarCropRequest(image: image)
        }
    }

    private func presentSourceMenuAfterCropDismisses() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            isChoosingSource = true
        }
    }
}

private struct AvatarCropRequest: Identifiable {
    let id = UUID()
    let image: UIImage
}

private enum AvatarCropImageLoader {
    nonisolated static func image(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail, scale: 1, orientation: .up)
    }
}

private extension UIImage {
    var preparedForAvatarCrop: UIImage {
        let maximumDimension: CGFloat = 2_048
        let largestSide = max(size.width, size.height)
        guard imageOrientation != .up || largestSide > maximumDimension else { return self }

        let resizeScale = min(maximumDimension / largestSide, 1)
        let targetSize = CGSize(width: size.width * resizeScale, height: size.height * resizeScale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
