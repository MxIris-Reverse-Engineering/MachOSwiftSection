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

    package var targetTriple: String {
        get throws {
            let arch: String
            #if arch(x86_64)
            arch = "x86_64"
            #elseif arch(arm64)
            arch = "arm64"
            #else
            return ""
            #endif
            let settingsPlistData = try Data(contentsOf: URL(fileURLWithPath: sdkPath).appending(path: "SDKSettings.plist"))
            guard let settingsPlist = try PropertyListSerialization.propertyList(from: settingsPlistData, format: nil) as? [String: Any], let version = settingsPlist["Version"] as? String else { return "" }

            switch self {
            case .macOS:
                return "\(arch)-apple-macos\(version)"
            case .iOS:
                return "\(arch)-apple-ios\(version)"
            case .tvOS:
                return "\(arch)-apple-tvos\(version)"
            case .watchOS:
                return "\(arch)-apple-watchos\(version)"
            case .visionOS:
                return "\(arch)-apple-xros\(version)"
            case .driverKit:
                return "\(arch)-apple-driverkit\(version)"
            case .iOSSimulator:
                return "\(arch)-apple-ios\(version)-simulator"
            case .tvOSSimulator:
                return "\(arch)-apple-tvos\(version)-simulator"
            case .watchOSSimulator:
                return "\(arch)-apple-watchos\(version)-simulator"
            case .visionOSSimulator:
                return "\(arch)-apple-xros\(version)-simulator"
            }
        }
    }
}
