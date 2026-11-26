import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
import SwiftSectionTestingSupport
@testable import MachOSwiftSection

/// The metadata an evolution pipeline reads, and so which images join its
/// axis: an image without it has nothing to index, and indexing it anyway
/// only logs extraction failures.
enum EvolutionMetadataLanguage: Sendable {
    /// `__swift5_*` sections. AppKit kept its Swift API in
    /// `libswiftAppKit.dylib` until macOS 14, so a Swift axis of AppKit
    /// reaching further back starts at 14.0.
    case swift
    /// `__objc_*` sections, which AppKit carries in every cache.
    case objc

    func isCarried(by machOFile: MachOFile) -> Bool {
        let sectionNamePrefix = switch self {
        case .swift: "__swift5_"
        case .objc: "__objc_"
        }
        return machOFile.sections.contains(where: { $0.sectionName.hasPrefix(sectionNamePrefix) })
    }
}

/// The platform an evolution interface spells availability for — what
/// `evolution --interface --emit-available --platform` passes — each
/// pipeline in its own spelling.
enum EvolutionAvailabilityPlatform: Sendable {
    case macOS

    /// The platform of `@available(macOS, …)`.
    var swiftSpelling: String {
        switch self {
        case .macOS: "macOS"
        }
    }

    /// The platform of `API_AVAILABLE(macos(…))`.
    var objcSpelling: String {
        switch self {
        case .macOS: "macos"
        }
    }
}

/// One image of one version on an evolution axis.
struct EvolutionImage: Sendable {
    let imageName: String
    let machOFile: MachOFile
}

/// One version on an evolution axis: its label and the images whose
/// declarations make it up, the primary image first.
struct EvolutionVersion: Sendable {
    let label: String
    let images: [EvolutionImage]

    var primaryImage: EvolutionImage { images[0] }

    /// This version as a pipeline reading `language` sees it: only the
    /// images carrying that metadata, or `nil` — off the axis — when the
    /// primary image does not.
    func keepingImages(carrying language: EvolutionMetadataLanguage) -> EvolutionVersion? {
        guard language.isCarried(by: primaryImage.machOFile) else { return nil }
        return EvolutionVersion(label: label, images: images.filter { language.isCarried(by: $0.machOFile) })
    }
}

/// One ordered series of versions (oldest first), as one pipeline reads it.
struct EvolutionAxis: Sendable {
    let versions: [EvolutionVersion]
    /// Whether every version is a group of images (evolution proposal
    /// `image-group-evolution`). It picks the builders' image-group entry
    /// points, which name each version's images and record moves between
    /// them, so a version of one image still reads differently from a group
    /// of one.
    let comparesImageGroups: Bool
    /// Set when every label is a version number, so the interfaces also
    /// spell each lifecycle one attribute or macro can express.
    let availabilityPlatform: EvolutionAvailabilityPlatform?
}

/// Extracts the same images from an *ordered series* of dyld shared caches —
/// the N-version counterpart of
/// `SwiftDiffableInterfaceBuilderTestSuite.CrossVersionDyldCacheImageTests`.
/// The caches are retained because the extracted `MachOFile`s resolve
/// cross-image references through them while indexing.
///
/// One instance serves every pipeline: it keeps, per cache, every image of
/// `cacheImageNames` the cache holds, and each language's axis then keeps
/// the images carrying that language's metadata. A version whose primary
/// image is missing, or lacks the metadata, is off that axis — there is
/// nothing to index. A cache that cannot be opened still throws.
///
/// Each cache is opened whole, the way `swift-section --dyld-shared-cache`
/// opens it, so the dumps match what the command line prints. Opened from
/// its main file alone, every read into another sub-cache file mapped that
/// file once more until MachOObjCSection 0.8.109, and an evolution over
/// every archived macOS minor ran past 5 GB.
///
/// A suite comparing a group of images per version (evolution proposal
/// `image-group-evolution`) lists them in `cacheImageNames`, the primary
/// image first: AppKit with the frameworks Apple moved its classes into,
/// SwiftUI with SwiftUICore. Each other image joins its group where the
/// cache has it with the metadata — CollectionViewCore is in the macOS
/// caches from 13.0 on, SwiftUICore from 15.0 on.
@TestActor
class MultiVersionDyldCacheImageTests: Sendable {
    let caches: [FullDyldCache]
    private let swiftAxis: EvolutionAxis
    private let objcAxis: EvolutionAxis

    /// Oldest first; each cache's `versionLabel` labels it on the axis.
    class var cachePaths: [DyldSharedCachePath] { defaultMacOSCachePaths }

    class var cacheImageName: MachOImageName { .SwiftUI }

    /// The images whose declarations make up one version, the primary
    /// image first; by default the primary image alone.
    class var cacheImageNames: [MachOImageName] { [cacheImageName] }

    /// Set on an axis whose every label is a version number.
    class var availabilityPlatform: EvolutionAvailabilityPlatform? { nil }

    /// The three macOS caches most suites read: 15.5 → 26.5.2 → 27.0.
    static var defaultMacOSCachePaths: [DyldSharedCachePath] {
        [.macOS_15_5, .macOS_26_5_2, .macOS_27_0]
    }

    /// One archived cache per macOS minor, oldest first: the directories
    /// under `/Volumes/DyldSharedCaches/macOS` that hold a cache. A cache is
    /// labeled with its version, or with the major release
    /// `archivedMacOSVersionLabelsByCacheVersion` names for it, so every label
    /// is a version number.
    static var archivedMacOSCachePaths: [DyldSharedCachePath] {
        archivedMacOSCacheVersions.map { cacheVersion in
            let cachePath = DyldSharedCachePath.macOS(cacheVersion)
            guard let versionLabel = archivedMacOSVersionLabelsByCacheVersion[cacheVersion] else { return cachePath }
            return DyldSharedCachePath(path: cachePath.path, versionLabel: versionLabel)
        }
    }

    static var archivedMacOSCacheVersions: [String] { [
        "11.0.1",
        "11.1",
        "11.2",
        "11.3",
        "11.4",
        "11.5",
        "11.6",
        "11.7",
        "12.0.1",
        "12.1",
        "12.2",
        "12.3",
        "12.4",
        "12.5",
        "12.6",
        "12.7",
        "13.0",
        "13.1",
        "13.2",
        "13.3",
        "13.4",
        "13.5",
        "13.6",
        "13.7",
        "14.0",
        "14.1",
        "14.2",
        "14.3",
        "14.4",
        "14.5",
        "14.6",
        "14.7",
        "14.8",
        "15.0",
        "15.1",
        "15.2",
        "15.3",
        "15.4",
        "15.5",
        "15.6",
        "15.7",
        "15.8",
        "26.0",
        "26.1",
        "26.2",
        "26.3",
        "26.4",
        "26.5",
        "26.6",
        "26.7",
        "27.0",
    ] }

    /// AppleDB offers no macOS 11.0 or 12.0 image, only 11.0.1 and 12.0.1,
    /// so those are the directories the volume has; the axis still labels
    /// them 11.0 and 12.0, the versions an SDK's availability attributes name.
    static var archivedMacOSVersionLabelsByCacheVersion: [String: String] {
        ["11.0.1": "11.0", "12.0.1": "12.0"]
    }

    init() async throws {
        let primaryImageName = Self.cacheImageNames.first?.name
        var caches: [FullDyldCache] = []
        var versions: [EvolutionVersion] = []
        for cachePath in Self.cachePaths {
            let cache = try FullDyldCache(path: cachePath)
            let images = Self.cacheImageNames.compactMap { imageName -> EvolutionImage? in
                guard let machOFile = cache.machOFile(named: imageName) else { return nil }
                return EvolutionImage(imageName: imageName.name, machOFile: machOFile)
            }
            guard let primaryImage = images.first, primaryImage.imageName == primaryImageName else {
                continue
            }
            caches.append(cache)
            versions.append(EvolutionVersion(label: cachePath.versionLabel, images: images))
        }
        let comparesImageGroups = Self.cacheImageNames.count > 1
        let availabilityPlatform = Self.availabilityPlatform
        self.caches = caches
        self.swiftAxis = EvolutionAxis(
            versions: versions.compactMap { $0.keepingImages(carrying: .swift) },
            comparesImageGroups: comparesImageGroups,
            availabilityPlatform: availabilityPlatform
        )
        self.objcAxis = EvolutionAxis(
            versions: versions.compactMap { $0.keepingImages(carrying: .objc) },
            comparesImageGroups: comparesImageGroups,
            availabilityPlatform: availabilityPlatform
        )
    }

    /// The axis a pipeline reading `language` runs over. Computed at
    /// initialization: the class properties it derives from are isolated to
    /// the test actor, the pipelines are not.
    nonisolated func evolutionAxis(for language: EvolutionMetadataLanguage) -> EvolutionAxis {
        switch language {
        case .swift: swiftAxis
        case .objc: objcAxis
        }
    }
}
