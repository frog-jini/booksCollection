import SwiftUI

@main
struct EyeReaderApp: App {
    @StateObject private var library = Library()
    @StateObject private var face = FaceTracker()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(library)
                .environmentObject(face)
        }
    }
}

enum Theme {
    static let background = Color(red: 0.98, green: 0.965, blue: 0.925)
    static let text = Color(red: 0.16, green: 0.16, blue: 0.16)
    static let read = Color(red: 0.63, green: 0.63, blue: 0.63)
    static let lineHighlight = Color(red: 1.0, green: 0.95, blue: 0.75)
    static let wordHighlight = Color(red: 1.0, green: 0.77, blue: 0.31)
    static let heat = Color(red: 0.9, green: 0.24, blue: 0.16)
    static let toast = Color(red: 0.24, green: 0.27, blue: 0.35)
}

enum SampleBook {
    static let title = "눈으로 넘기는 책 (샘플)"
    static let text = """
    눈으로 넘기는 책

    이 글은 앱이 어떻게 동작하는지 보여 주기 위한 연습용 글입니다. 폰을 평소 책 읽는 자세로 들고, 머리는 편하게 둔 채 눈으로만 한 줄씩 읽어 보세요. 지금 보고 있는 단어는 주황색으로, 지금 읽는 줄은 연한 노란색으로 표시됩니다.

    이미 읽은 단어는 회색으로 바뀝니다. 줄 끝까지 읽은 다음 다시 왼쪽 끝으로 돌아가면 다음 줄로 넘어갑니다. 사람이 책을 읽을 때 눈이 줄 끝에서 다음 줄 처음으로 휙 돌아가는 움직임을 따라 한 것입니다.

    페이지의 마지막 줄까지 읽고 나서 마지막 단어를 잠깐 바라보거나 왼쪽 끝으로 돌아가면 페이지가 저절로 넘어갑니다. 얼마나 오래 보고 있어야 넘어가는지는 읽는 속도에 맞춰 바뀝니다.

    읽는 동안 화면 아래에는 읽기 속도와 집중도, 자세, 화면과의 거리가 표시됩니다. 얼굴을 화면에 너무 가까이 대거나 고개를 오래 기울이고 있으면 위쪽에 알림이 뜨고, 오래 읽으면 쉬어 가라고 알려 줍니다. 눈을 자주 오래 감으면 졸음도 알려 줍니다.

    두 번째 페이지까지 넘어왔다면 성공입니다. 손가락으로 화면을 옆으로 밀어서 페이지를 직접 넘길 수도 있습니다. 아래 버튼으로 시선 점과 heatmap 을 켜고 끌 수 있고, 다 읽은 뒤 끝내기를 누르면 독서 보고서가 만들어집니다.

    이제 서재에서 txt 나 pdf 파일을 가져오거나, 무료 책 검색으로 공개 도서를 찾아 읽어 보세요.
    """
}
