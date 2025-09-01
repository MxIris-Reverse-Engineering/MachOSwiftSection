import Foundation

public enum SKPlatform: String, CaseIterable, Hashable, Codable, Sendable {
    case macOS = "macosx"
    case iOS = "iphoneos"
    case tvOS = "appletvos"
    case watchOS = "watchos"
    case driverKit = "driverkit"
    case tvSimulator = "appletvsimulator"
    case watchSimulator = "watchsimulator"
    case iPhoneSimulator = "iphonesimulator"

    public var sdkPath: String {
        SKSubprocess.xcRun(arguments: ["--show-sdk-path", "--sdk", rawValue]) ?? ""
    }
}
