import SwiftUI

/// 앱 아이콘의 하트. 이 앱의 로고는 이것 하나다.
///
/// 배경이 칠해진 PNG라 알파가 없다. 검은 바탕 위에서만 테두리 없이 얹히니
/// 밝은 표면에 올리려면 알파 있는 에셋을 따로 만들어야 한다.
struct HeartMark: View {
    var size: CGFloat

    var body: some View {
        Image("HeartMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// 하트에 이름을 붙인 가로 조합. 로고 혼자 서는 자리에는 HeartMark를 그대로 쓴다.
struct BrandMark: View {
    var body: some View {
        HStack(spacing: Metric.s) {
            HeartMark(size: 34)

            Text("Way to You")
                .font(.rounded(.headline, .semibold))
                .foregroundStyle(Palette.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Way to You")
    }
}

#Preview("브랜드 마크") {
    ZStack {
        Palette.spaceDeep.ignoresSafeArea()
        VStack(spacing: Metric.xxl) {
            HeartMark(size: 132)
            BrandMark()
        }
    }
}
