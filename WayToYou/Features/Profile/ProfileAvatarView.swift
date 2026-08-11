import SwiftUI
import UIKit

struct ProfileAvatarImage: View {
    let data: Data?
    let displayName: String
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(white: 0.12)
                    Text(initial)
                        .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(Color.white.opacity(0.92), lineWidth: max(size * 0.045, 2))
        }
        .shadow(color: .black.opacity(0.45), radius: 7, y: 3)
        .accessibilityLabel(data == nil ? "\(displayName) 기본 프로필" : "\(displayName) 프로필 사진")
    }

    private var initial: String {
        let cleaned = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.first.map { String($0).uppercased() } ?? "?"
    }
}
