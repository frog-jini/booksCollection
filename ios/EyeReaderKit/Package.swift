// swift-tools-version: 6.0
// 아이폰 앱의 핵심 로직. 화면·카메라와 상관없는 계산만 담아서 Linux/Mac 어디서나 테스트할 수 있다.
import PackageDescription

let package = Package(
    name: "EyeReaderKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "EyeReaderKit", targets: ["EyeReaderKit"])],
    targets: [
        .target(name: "EyeReaderKit"),
        .testTarget(name: "EyeReaderKitTests", dependencies: ["EyeReaderKit"]),
    ]
)
