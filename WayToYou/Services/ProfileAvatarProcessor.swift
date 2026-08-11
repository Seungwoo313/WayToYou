import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ProfileAvatarProcessingError: Error {
    case invalidImage
    case encodingFailed
    case fileTooLarge
}

/// 원본 전체를 디코딩하지 않고 축소한 뒤 정사각형 JPEG로 다시 만든다.
/// 이 과정에서 EXIF를 비롯한 원본 메타데이터도 함께 제거된다.
enum ProfileAvatarProcessor {
    private static let outputPixels = 512
    private static let decodePixels = 1_024
    private static let maximumBytes = 1_048_576

    nonisolated static func jpegData(from data: Data) throws -> Data {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ProfileAvatarProcessingError.invalidImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: decodePixels
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            throw ProfileAvatarProcessingError.invalidImage
        }

        let side = min(thumbnail.width, thumbnail.height)
        let crop = CGRect(
            x: CGFloat(thumbnail.width - side) / 2,
            y: CGFloat(thumbnail.height - side) / 2,
            width: CGFloat(side),
            height: CGFloat(side)
        )
        guard let square = thumbnail.cropping(to: crop) else {
            throw ProfileAvatarProcessingError.invalidImage
        }

        guard let context = CGContext(
            data: nil,
            width: outputPixels,
            height: outputPixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ProfileAvatarProcessingError.encodingFailed
        }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        let outputSize = CGFloat(outputPixels)
        context.fill(CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
        context.draw(
            square,
            in: CGRect(x: 0, y: 0, width: outputSize, height: outputSize)
        )
        guard let output = context.makeImage() else {
            throw ProfileAvatarProcessingError.encodingFailed
        }

        for quality in [0.82, 0.68, 0.52] {
            let encoded = try encode(output, quality: quality)
            if encoded.count <= maximumBytes { return encoded }
        }
        throw ProfileAvatarProcessingError.fileTooLarge
    }

    nonisolated private static func encode(_ image: CGImage, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ProfileAvatarProcessingError.encodingFailed
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw ProfileAvatarProcessingError.encodingFailed
        }
        return output as Data
    }
}
