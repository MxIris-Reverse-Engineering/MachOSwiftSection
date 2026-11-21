import MachOFixtureSupport

/// The caches this package's tests name, beside the running system's
/// (`current`) and the archived ones any version names (`macOS(_:)`,
/// `iOS(_:)`) that MachOKitExtensions provides.
extension DyldSharedCachePath {
    package static let iOS_18_5 = DyldSharedCachePath(path: "/Volumes/Generic/iOS Systems/22F76__iPhone17,5/dyld_shared_cache_arm64e", versionLabel: "18.5")
    package static let iOS_26_1 = DyldSharedCachePath(path: "/Volumes/Generic/iOS Systems/23B85__iPhone17,5/dyld_shared_cache_arm64e", versionLabel: "26.1")
    package static let macOS_15_5 = macOS("15.5")
    package static let macOS_26_5_1 = macOS("26.5.1")
    package static let macOS_26_5_2 = macOS("26.5.2")
    package static let macOS_27_0 = macOS("27.0")
    /// From iOS 27 beta 3 on a simulator runtime ships its frameworks in a
    /// cache of its own instead of as files under `RuntimeRoot`. The runtime's
    /// volume is named after its build, so no version alone spells this path.
    package static let iOS_27_0_Simulator = DyldSharedCachePath(path: "/Library/Developer/CoreSimulator/Volumes/iOS_24A434/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.0.simruntime/Contents/Resources/RuntimeRoot/System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64", versionLabel: "27.0")
}
