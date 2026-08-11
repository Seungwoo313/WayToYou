import SwiftUI
import UIKit

@MainActor
final class ProfileAvatarCropController {
    weak var cropView: ProfileAvatarZoomView?

    func visibleSquareJPEGData() throws -> Data {
        guard let cropView else { throw ProfileAvatarProcessingError.invalidImage }
        return try cropView.visibleSquareJPEGData()
    }
}

struct ProfileAvatarZoomCanvas: UIViewRepresentable {
    let image: UIImage
    let controller: ProfileAvatarCropController

    func makeUIView(context: Context) -> ProfileAvatarZoomView {
        let view = ProfileAvatarZoomView(image: image)
        controller.cropView = view
        return view
    }

    func updateUIView(_ uiView: ProfileAvatarZoomView, context: Context) {
        uiView.setImageIfNeeded(image)
        controller.cropView = uiView
    }

    static func dismantleUIView(_ uiView: ProfileAvatarZoomView, coordinator: Void) {
        uiView.stopScrolling()
    }
}

final class ProfileAvatarZoomView: UIView, UIScrollViewDelegate {
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private var image: UIImage
    private var configuredSize: CGSize = .zero

    init(image: UIImage) {
        self.image = image
        super.init(frame: .zero)

        backgroundColor = .black
        clipsToBounds = true

        scrollView.delegate = self
        scrollView.backgroundColor = .black
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.decelerationRate = .fast
        scrollView.bounces = false
        scrollView.bouncesZoom = false
        scrollView.contentInsetAdjustmentBehavior = .never

        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false

        scrollView.addSubview(imageView)
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds

        guard bounds.width > 0,
              bounds.height > 0,
              configuredSize != bounds.size else { return }
        configuredSize = bounds.size
        configureInitialZoom()
    }

    func setImageIfNeeded(_ newImage: UIImage) {
        guard image !== newImage else { return }
        image = newImage
        imageView.image = newImage
        configuredSize = .zero
        setNeedsLayout()
    }

    func stopScrolling() {
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        scrollView.contentInset = .zero
    }

    func visibleSquareJPEGData() throws -> Data {
        layoutIfNeeded()
        settleForCapture()

        let visibleRect = scrollView.convert(scrollView.bounds, to: imageView)
        let sourceBounds = imageView.bounds
        let sourceSide = min(
            min(visibleRect.width, visibleRect.height),
            min(sourceBounds.width, sourceBounds.height)
        )
        guard sourceSide > 1 else { throw ProfileAvatarProcessingError.invalidImage }

        let proposedX = visibleRect.midX - sourceSide / 2
        let proposedY = visibleRect.midY - sourceSide / 2
        let maximumOriginX = max(sourceBounds.maxX - sourceSide, sourceBounds.minX)
        let maximumOriginY = max(sourceBounds.maxY - sourceSide, sourceBounds.minY)
        let sourceRect = CGRect(
            x: min(max(proposedX, sourceBounds.minX), maximumOriginX),
            y: min(max(proposedY, sourceBounds.minY), maximumOriginY),
            width: sourceSide,
            height: sourceSide
        )

        let outputPixels: CGFloat = 512
        let outputScale = outputPixels / sourceRect.width
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let result = UIGraphicsImageRenderer(
            size: CGSize(width: outputPixels, height: outputPixels),
            format: format
        ).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: outputPixels, height: outputPixels))
            image.draw(
                in: CGRect(
                    x: -sourceRect.minX * outputScale,
                    y: -sourceRect.minY * outputScale,
                    width: image.size.width * outputScale,
                    height: image.size.height * outputScale
                )
            )
        }

        for quality in [0.82, 0.68, 0.52] {
            guard let data = result.jpegData(compressionQuality: quality) else { continue }
            if data.count <= 1_048_576 { return data }
        }
        throw ProfileAvatarProcessingError.fileTooLarge
    }

    private func configureInitialZoom() {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        imageView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize
        scrollView.contentInset = .zero

        let fillScale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        scrollView.minimumZoomScale = fillScale
        scrollView.maximumZoomScale = fillScale * 5
        scrollView.setZoomScale(fillScale, animated: false)
        scrollView.layoutIfNeeded()

        let offsetX = max((scrollView.contentSize.width - bounds.width) / 2, 0)
        let offsetY = max((scrollView.contentSize.height - bounds.height) / 2, 0)
        scrollView.setContentOffset(CGPoint(x: offsetX, y: offsetY), animated: false)
        scrollView.contentInset = .zero
    }

    private func settleForCapture() {
        scrollView.layer.removeAllAnimations()
        scrollView.setZoomScale(
            min(max(scrollView.zoomScale, scrollView.minimumZoomScale), scrollView.maximumZoomScale),
            animated: false
        )
        scrollView.contentInset = .zero
        scrollView.layoutIfNeeded()

        let maximumX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
        let maximumY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        let settledOffset = CGPoint(
            x: min(max(scrollView.contentOffset.x, 0), maximumX),
            y: min(max(scrollView.contentOffset.y, 0), maximumY)
        )
        scrollView.setContentOffset(settledOffset, animated: false)
        scrollView.layoutIfNeeded()
    }
}
