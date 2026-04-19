// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_pdf_annotations",
    platforms: [
        .iOS("14.0")
    ],
    products: [
        .library(name: "flutter-pdf-annotations", targets: ["flutter_pdf_annotations"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "flutter_pdf_annotations",
            dependencies: [],
            path: "../Classes",
            resources: [
                .process("../Resources/PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
