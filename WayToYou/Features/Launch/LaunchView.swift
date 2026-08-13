import SwiftUI

/// 앱을 켤 때 처음 보이는 화면. 로고 하나만 둔다.
///
/// 세션 복원과 연결 확인은 코드에선 다른 단계지만, 켜는 사람에게는 한 번의 기다림이다.
/// 예전엔 두 단계가 각자 다른 화면을 띄워서, 로그인 화면이 스쳤다가
/// 까만 화면으로 갈아치워지고 나서야 홈이 나왔다.
/// 문구도 스피너도 없이 같은 화면을 끝까지 유지하는 편이 조용하다.
struct LaunchView: View {
    /// 하트가 한 번 다 밝아지는 데 걸리는 시간. ContentView가 이만큼은 화면을 붙잡아둔다.
    static let brightenDuration: Duration = .milliseconds(1_200)

    @State private var isBreathing = false

    var body: some View {
        ZStack {
            Palette.spaceDeep.ignoresSafeArea()

            // 어두운 데서 서서히 밝아졌다가 다시 가라앉기를 반복한다.
            HeartMark(size: 132)
                .opacity(isBreathing ? 1 : 0.55)
                .animation(
                    .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                    value: isBreathing
                )
        }
        .onAppear { isBreathing = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Way to You, 준비하고 있어요")
    }
}

#Preview("시작 화면") {
    LaunchView()
}
