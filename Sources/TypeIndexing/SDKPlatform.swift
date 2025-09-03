import Foundation

package enum SDKPlatform: String, CaseIterable, Hashable, Codable, Sendable {
    case macOS = "macosx"
    case iOS = "iphoneos"
    case tvOS = "appletvos"
    case watchOS = "watchos"
    case visionOS = "xros"
    case driverKit = "driverkit"
    case iOSSimulator = "iphonesimulator"
    case tvOSSimulator = "appletvsimulator"
    case watchOSSimulator = "watchsimulator"
    case visionOSSimulator = "xrsimulator"

    package var sdkPath: String {
        Subprocess.xcRun(arguments: ["--show-sdk-path", "--sdk", rawValue]) ?? ""
    }
}
