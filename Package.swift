// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GuanWei",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GuanWei",
            path: "Sources/GuanWei",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
