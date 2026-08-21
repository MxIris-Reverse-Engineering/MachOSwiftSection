#if os(macOS)

import Foundation

/// An Apple SDK the indexer can point SourceKit at, named by its
/// `xcrun --sdk` identifier.
@available(macOS 13.0, *)
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

    /// The on-disk root of this platform's SDK in the active Xcode.
    package func sdkPath() throws -> String {
        try Subprocess.xcrun(["--show-sdk-path", "--sdk", rawValue])
    }

    /// The settings of this platform's SDK in the active Xcode. Reads
    /// `SDKSettings.plist` once per call; callers cache the result.
    package func sdkSettings() throws -> SDKSettings {
        try SDKSettings(sdkPath: sdkPath())
    }
}

/// The subset of an SDK's `SDKSettings.plist` the indexer consumes: enough to
/// form a compiler target triple and to version the on-disk index cache.
@available(macOS 13.0, *)
package struct SDKSettings: Sendable {
    package let sdkPath: String

    /// The SDK's marketing version, e.g. `26.5`.
    package let version: String

    /// The SDK's build identifier, e.g. `25F76`. Distinguishes beta builds
    /// that share a marketing version. Absent from some SDKs.
    package let productBuildVersion: String?

    enum Error: Swift.Error {
        case malformedSDKSettings(path: String)
    }

    package init(sdkPath: String) throws {
        let settingsPlistURL = URL(fileURLWithPath: sdkPath).appending(component: "SDKSettings.plist")
        let settingsPlistData = try Data(contentsOf: settingsPlistURL)
        guard
            let settingsPlist = try PropertyListSerialization.propertyList(from: settingsPlistData, format: nil) as? [String: Any],
            let version = settingsPlist["Version"] as? String
        else {
            throw Error.malformedSDKSettings(path: settingsPlistURL.path(percentEncoded: false))
        }
        self.sdkPath = sdkPath
        self.version = version
        self.productBuildVersion = settingsPlist["ProductBuildVersion"] as? String
    }

    /// One path component identifying this exact SDK build, used to segment
    /// the on-disk index cache so an Xcode update never serves stale entries.
    package var cacheDirectoryComponent: String {
        if let productBuildVersion {
            return "\(version)-\(productBuildVersion)"
        }
        return version
    }

    /// The compiler target triple for `platform` at this SDK's version, for
    /// the host architecture.
    package func targetTriple(for platform: SDKPlatform) -> String {
        let architecture: String
        #if arch(x86_64)
        architecture = "x86_64"
        #elseif arch(arm64)
        architecture = "arm64"
        #else
        architecture = "unknown"
        #endif
        switch platform {
        case .macOS:
            return "\(architecture)-apple-macos\(version)"
        case .iOS:
            return "\(architecture)-apple-ios\(version)"
        case .tvOS:
            return "\(architecture)-apple-tvos\(version)"
        case .watchOS:
            return "\(architecture)-apple-watchos\(version)"
        case .visionOS:
            return "\(architecture)-apple-xros\(version)"
        case .driverKit:
            return "\(architecture)-apple-driverkit\(version)"
        case .iOSSimulator:
            return "\(architecture)-apple-ios\(version)-simulator"
        case .tvOSSimulator:
            return "\(architecture)-apple-tvos\(version)-simulator"
        case .watchOSSimulator:
            return "\(architecture)-apple-watchos\(version)-simulator"
        case .visionOSSimulator:
            return "\(architecture)-apple-xros\(version)-simulator"
        }
    }
}

#endif
