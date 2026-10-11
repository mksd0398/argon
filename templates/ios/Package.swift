// swift-tools-version: 6.0
import PackageDescription

// For building without Xcode: xtool (https://xtool.sh) builds this package into the app on Linux or Windows (WSL)
// and installs it on an iPhone. The sources are the ones App.xcodeproj builds; xtool needs exactly one library
// product, the app. See README.md, "iOS without a Mac".
let package = Package(
    name: "ArgonStorefront",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ArgonStorefront", targets: ["ArgonStorefront"]),
    ],
    dependencies: [
        .package(path: "ArgonUI"),
        .package(url: "https://github.com/Shopify/checkout-sheet-kit-swift", from: "3.9.1"),
    ],
    targets: [
        .target(
            name: "ArgonStorefront",
            dependencies: [
                "ArgonUI",
                .product(name: "ShopifyCheckoutSheetKit", package: "checkout-sheet-kit-swift"),
            ],
            path: "App",
            // xtool.yml copies these to the app's top level instead: the app reads them from Bundle.main. The asset
            // catalog (the Xcode build's icon and launch screen) is left out: xtool can't compile one, and takes its
            // icon from xtool.yml's iconPath.
            exclude: ["Resources", "PrivacyInfo.xcprivacy", "Assets.xcassets"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
