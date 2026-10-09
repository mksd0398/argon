// swift-tools-version: 5.10
import PackageDescription

// Argon's component library: SwiftUI only, no app code and no Shopify types (callers pass plain values).
let package = Package(
    name: "ArgonUI",
    platforms: [.iOS(.v17)],
    products: [.library(name: "ArgonUI", targets: ["ArgonUI"])],
    targets: [
        .target(name: "ArgonUI", resources: [.copy("Resources/Fonts")]),
    ]
)
