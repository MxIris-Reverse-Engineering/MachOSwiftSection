import MachOKit

/// The platforms a Mach-O declares itself built for, as `FileDependencyLocator`
/// compares a root binary against a dyld shared cache's images (evolution
/// proposal `objc-ancestor-dependency-closure`).
///
/// A cache is a per-platform artifact, but the running system's cache is the
/// default search path for every root, and a macOS cache carries the Mac
/// Catalyst builds of UIKit, SwiftUI and friends under `/System/iOSSupport`
/// wearing the same bare names an iOS root links. Ranking demotes them behind
/// a native build, but for an iOS root there is no native build to win, so
/// the bare-name fallback handed back a Catalyst UIKit — same class names,
/// different platform, different method tables — and every consumer reading
/// facts out of it (an ObjC ancestor's selectors, an instance size) read the
/// wrong platform's. The locator now skips a cache image whose platforms are
/// disjoint from the root's.
public enum DependencyPlatforms {
    /// Every `LC_BUILD_VERSION` platform (a zippered macOS + Mac Catalyst
    /// image carries two); with none, the platform an `LC_VERSION_MIN_*`
    /// command implies; empty when the image declares nothing — an old or
    /// unusual binary, which the guard then lets through rather than
    /// refusing every candidate.
    public static func platforms(of machO: some MachORepresentable) -> Set<Platform> {
        let loadCommands = machO.loadCommands
        let declared = Set(loadCommands.infos(of: LoadCommand.buildVersion).map(\.platform))
        if !declared.isEmpty { return declared }
        var implied: Set<Platform> = []
        if loadCommands.info(of: LoadCommand.versionMinMacosx) != nil { implied.insert(.macOS) }
        if loadCommands.info(of: LoadCommand.versionMinIphoneos) != nil { implied.insert(.iOS) }
        if loadCommands.info(of: LoadCommand.versionMinTvos) != nil { implied.insert(.tvOS) }
        if loadCommands.info(of: LoadCommand.versionMinWatchos) != nil { implied.insert(.watchOS) }
        return implied
    }

    /// Whether an image built for `candidatePlatforms` may stand in for a
    /// dependency of a root built for `rootPlatforms`: the two share a
    /// platform, or one side declares none. A simulator platform and its
    /// device platform are distinct — an `iOSSimulator` root never takes an
    /// `iOS` cache's image, nor a `macCatalyst` one.
    public static func areCompatible(_ rootPlatforms: Set<Platform>, _ candidatePlatforms: Set<Platform>) -> Bool {
        rootPlatforms.isEmpty || candidatePlatforms.isEmpty || !rootPlatforms.isDisjoint(with: candidatePlatforms)
    }
}
