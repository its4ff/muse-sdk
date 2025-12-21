// swift-tools-version:5.9
import PackageDescription

// BCLRingSDK is a pre-compiled xcframework that has RxSwift, Foil, NordicDFU,
// SwiftDate, SwiftyBeaver, and ZIPFoundation statically linked inside.
//
// We must include these as SPM dependencies because BCLRingSDK's swiftinterface
// files contain `import` statements for these modules. Swift needs to resolve
// these at compile time.
//
// NOTE: This causes duplicate class warnings at runtime because the same code
// exists in both BCLRingSDK (statically linked) and the SPM packages. These
// warnings are harmless but noisy.

let package = Package(
    name: "MuseSDK",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "MuseSDK",
            targets: ["MuseSDK"]
        )
    ],
    dependencies: [
        // Required for BCLRingSDK swiftinterface module resolution
        .package(url: "https://github.com/jessesquires/Foil.git", from: "5.1.2"),
        .package(url: "https://github.com/NordicSemiconductor/IOS-DFU-Library.git", from: "4.16.0"),
        .package(url: "https://github.com/ReactiveX/RxSwift.git", from: "6.9.0"),
        .package(url: "https://github.com/malcommac/SwiftDate.git", from: "7.0.0"),
        .package(url: "https://github.com/SwiftyBeaver/SwiftyBeaver.git", from: "1.9.5"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "MuseSDK",
            dependencies: [
                "BCLRingSDK",
                "Foil",
                .product(name: "NordicDFU", package: "IOS-DFU-Library"),
                "RxSwift",
                .product(name: "RxCocoa", package: "RxSwift"),
                .product(name: "RxRelay", package: "RxSwift"),
                "SwiftDate",
                "SwiftyBeaver",
                "ZIPFoundation",
            ],
            path: "Sources/MuseSDK"
        ),
        .binaryTarget(
            name: "BCLRingSDK",
            path: "Frameworks/BCLRingSDK.xcframework"
        )
    ]
)
