import PhotosUI
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

struct ProfileAvatarPicker: View {
    @Binding var selection: PhotosPickerItem?

    let data: Data?
    let displayName: String
    let isWorking: Bool
    var size: CGFloat = 76

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatarImage(data: data, displayName: displayName, size: size)

                Image(systemName: data == nil ? "plus" : "pencil")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 23, height: 23)
                    .background(Color.black, in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: 1) }
            }
            .overlay {
                if isWorking {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: size, height: size)
                        .overlay { ProgressView().tint(.white) }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityHint("사진 보관함에서 새 프로필 사진을 선택합니다")
    }
}
