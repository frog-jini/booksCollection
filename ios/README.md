# 눈으로 읽기 — 아이폰 앱

Face ID 카메라(ARKit)로 시선을 추적해 읽는 줄·단어를 색으로 표시하고, 다 읽으면 페이지를 넘깁니다.
읽는 동안 화면 거리·자세·휴식·졸음·집중도를 알려 주고, 끝나면 독서 보고서(JSON)를 만듭니다.

- `EyeReaderKit/` : 핵심 로직(시선 계산·보정·줄 추적·자세·졸음·집중도·heatmap·구텐베르크). `swift test` 로 테스트.
- `App/` : 아이폰 화면(SwiftUI)과 카메라(ARKit) 연결.
- `project.yml` : Xcode 프로젝트 설정(XcodeGen).

## 맥에서 아이폰에 설치하기

1. App Store 에서 **Xcode** 설치(처음 한 번, 용량이 큽니다). 설치 후 한 번 실행해서 추가 구성요소를 설치합니다.
2. 터미널에서:
   ```bash
   brew install xcodegen
   cd ~/booksCollection/ios
   xcodegen            # EyeReader.xcodeproj 생성
   open EyeReader.xcodeproj
   ```
3. Xcode 왼쪽에서 **EyeReader** 프로젝트 → TARGETS 의 **EyeReader** → **Signing & Capabilities**
   - **Team**: `Add an Account…` 로 애플 계정 로그인 후 `(Personal Team)` 선택
   - 'Bundle Identifier 가 이미 쓰이고 있다'는 오류가 나면 `com.jini.eyereader` 끝에 숫자 등을 붙여 바꾸세요.
4. 아이폰을 케이블로 연결 → 아이폰에서 **이 컴퓨터를 신뢰**.
   아이폰 **설정 → 개인정보 보호 및 보안 → 개발자 모드** 켜기(재시동됨).
5. Xcode 위쪽 기기 목록에서 내 아이폰을 고르고 ▶(Run).
6. 처음 실행하면 아이폰에서 "신뢰할 수 없는 개발자" 가 뜹니다:
   **설정 → 일반 → VPN 및 기기 관리 → (내 애플 계정) → 신뢰**. 그다음 앱을 다시 엽니다.

무료 애플 계정으로 설치한 앱은 **7일** 동안 쓸 수 있고, 그 뒤엔 5번을 다시 하면 됩니다.

## 쓰는 법

1. **시선 보정하기**: 평소 읽는 자세로 폰을 들고 빨간 점 9개를 눈으로 따라갑니다.
2. **샘플 책 읽기** 또는 **파일 가져오기**(txt·pdf) / **무료 책 검색**(Project Gutenberg).
3. 읽기 화면 아래 버튼: ◀ ▶ 페이지 · 시선 점 · heatmap · 다시 보정 · 끝내기(보고서).
   화면을 옆으로 밀어도 페이지가 넘어갑니다.
4. 보고서·책 파일은 **파일 앱 → 나의 iPhone → 눈으로 읽기** 에서 볼 수 있습니다.

## 한계

- 아이폰은 앱이 뒤로 가면 카메라가 꺼지므로, 다른 앱(네이버 시리즈 등)을 읽는 동안에는 동작하지 않습니다.
- DRM 이 걸린 전자책은 열 수 없습니다(txt·텍스트 PDF·무료 공개 도서).
