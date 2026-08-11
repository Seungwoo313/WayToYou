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
        NavigationStack {
            GeometryReader { proxy in
                let cropSide = max(min(proxy.size.width, proxy.size.height - 32), 160)

                ZStack {
                    Color(uiColor: .secondarySystemBackground).ignoresSafeArea()

                    cropCanvas(size: cropSide)

                    if let saveMessage {
                        Text(saveMessage)
                            .font(.rounded(.caption, .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 40)
                            .background(Color.white.opacity(0.14), in: Capsule())
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        onComplete(nil)
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("완료")
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .toolbarBackground(Color(uiColor: .secondarySystemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(.white)
        .preferredColorScheme(.dark)
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
