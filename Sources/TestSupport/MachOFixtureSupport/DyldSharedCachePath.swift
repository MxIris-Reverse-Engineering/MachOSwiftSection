/// A dyld shared cache file the tests open, and what a version axis calls it.
///
/// A struct with static members rather than an enum, so that besides the
/// caches named below any archived cache can be named by its version:
/// `.macOS("26.6")`. Not `RawRepresentable`: every value carries a label,
/// which a path alone does not give.
package struct DyldSharedCachePath: Hashable, Sendable {
    package let rawValue: String

    /// What a version axis calls this cache, such as the evolution dumps'
    /// labels: the version an archived cache was named by, or the label a
    /// named cache states. Not necessarily a system version — `current` is
    /// labeled `current`.
    package let versionLabel: String

    package init(rawValue: String, versionLabel: String) {
        self.rawValue = rawValue
        self.versionLabel = versionLabel
    }

    /// The archived macOS cache of `version`, labeled `version`:
    /// `/Volumes/DyldSharedCaches/macOS/<version>/dyld_shared_cache_arm64e`.
    ///
    /// `version` is the directory name on the volume (`26.5.2`,
    /// `14.0(Internal)`). Whether that directory holds a cache is the
    /// caller's to check; some hold only exported headers.
    package static func macOS(_ version: String) -> DyldSharedCachePath {
        archived(platformDirectoryName: "macOS", version: version)
    }

    /// The archived iOS device cache of `version`, labeled `version`:
    /// `/Volumes/DyldSharedCaches/iOS/<version>/dyld_shared_cache_arm64e`.
    package static func iOS(_ version: String) -> DyldSharedCachePath {
        archived(platformDirectoryName: "iOS", version: version)
    }

    private static func archived(platformDirectoryName: String, version: String) -> DyldSharedCachePath {
        DyldSharedCachePath(
            rawValue: "/Volumes/DyldSharedCaches/\(platformDirectoryName)/\(version)/dyld_shared_cache_arm64e",
            versionLabel: version
        )
    }

    /// The running system's cache.
    package static let current = DyldSharedCachePath(rawValue: "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e", versionLabel: "current")
    package static let iOS_18_5 = DyldSharedCachePath(rawValue: "/Volumes/Generic/iOS Systems/22F76__iPhone17,5/dyld_shared_cache_arm64e", versionLabel: "18.5")
    package static let iOS_26_1 = DyldSharedCachePath(rawValue: "/Volumes/Generic/iOS Systems/23B85__iPhone17,5/dyld_shared_cache_arm64e", versionLabel: "26.1")
    package static let macOS_15_5 = macOS("15.5")
    package static let macOS_26_5_1 = macOS("26.5.1")
    package static let macOS_26_5_2 = macOS("26.5.2")
    package static let macOS_27_0 = macOS("27.0")
    /// From iOS 27 beta 3 on a simulator runtime ships its frameworks in a
    /// cache of its own instead of as files under `RuntimeRoot`. The runtime's
    /// volume is named after its build, so no version alone spells this path.
    package static let iOS_27_0_Simulator = DyldSharedCachePath(rawValue: "/Library/Developer/CoreSimulator/Volumes/iOS_24A434/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.0.simruntime/Contents/Resources/RuntimeRoot/System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64", versionLabel: "27.0")
}
