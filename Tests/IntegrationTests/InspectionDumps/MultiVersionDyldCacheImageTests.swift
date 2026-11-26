import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
import SwiftSectionTestingSupport
@testable import MachOSwiftSection
import FoundationToolbox
import SwiftStdlibToolbox

/// The images a dyld shared cache suite reads out of each cache, the
/// primary image first. More than one makes every version a group of images
/// (evolution proposal `image-group-evolution`): AppKit with the frameworks
/// Apple moved its classes into, SwiftUI with SwiftUICore. Each other image
/// joins its group where the cache has it with the metadata —
/// CollectionViewCore is in the macOS caches from 13.0 on, SwiftUICore from
/// 15.0 on.
///
/// A suite points at one of these; to look at another framework, add one and
/// point the suite at it.
struct CacheImagesConfiguration: Sendable {
    let imageNames: [MachOImageName]

    static var swiftUI: Self { Self(imageNames: [.SwiftUI]) }
    static var swiftUICore: Self { Self(imageNames: [.SwiftUICore]) }
    /// AppKit kept its Swift API in `libswiftAppKit.dylib` until macOS 14,
    /// so its Swift axis starts at 14.0; its Objective-C metadata is in every
    /// cache.
    static var appKit: Self { Self(imageNames: [.AppKit]) }
    static var swiftUIGroup: Self { Self(imageNames: [.SwiftUI, .SwiftUICore]) }
    static var appKitGroup: Self { Self(imageNames: [.AppKit, .UIFoundation, .CollectionViewCore, .CoreAutoLayout]) }
}

/// Extracts the same images from an *ordered series* of dyld shared caches:
/// N versions for an evolution, two for a diff. The caches are retained
/// because the extracted `MachOFile`s resolve cross-image references through
/// them while indexing.
///
/// One instance serves every pipeline: it keeps, per cache, every image of
/// `configuration` the cache holds, and each language's axis then keeps
/// the images carrying that language's metadata. A version whose primary
/// image is missing, or lacks the metadata, is off that axis — there is
/// nothing to index. A cache that cannot be opened still throws.
///
/// Each cache is opened whole, the way `swift-section --dyld-shared-cache`
/// opens it, so the dumps match what the command line prints. Opened from
/// its main file alone, every read into another sub-cache file mapped that
/// file once more until MachOObjCSection 0.8.109, and an evolution over
/// every archived macOS minor ran past 5 GB. A diff reads the primary image
/// of each version only.
@TestActor
class MultiVersionDyldCacheImageTests: Sendable {
    let caches: [FullDyldCache]
    private let axes: VersionAxes

    /// Oldest first; each cache's `versionLabel` labels it on the axis.
    class var cachePaths: [DyldSharedCachePath] { defaultMacOSCachePaths }

    /// The images whose declarations make up one version.
    class var configuration: CacheImagesConfiguration { .swiftUI }

    /// Set on an axis whose every label is a version number.
    class var availabilityPlatform: AvailabilityPlatform? { nil }

    /// The three macOS caches most evolution suites read: 15.5 → 26.5.2 → 27.0.
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
        let imageNames = Self.configuration.imageNames
        let primaryImageName = imageNames.first?.name
        var caches: [FullDyldCache] = []
        var versions: [AxisVersion] = []
        for cachePath in Self.cachePaths {
            let cache = try FullDyldCache(path: cachePath)
            let images = imageNames.compactMap { imageName -> AxisImage? in
                guard let machOFile = cache.machOFile(named: imageName) else { return nil }
                return AxisImage(imageName: imageName.name, machOFile: machOFile)
            }
            guard let primaryImage = images.first, primaryImage.imageName == primaryImageName else {
                continue
            }
            caches.append(cache)
            versions.append(AxisVersion(label: cachePath.versionLabel, images: images))
        }
        self.caches = caches
        self.axes = VersionAxes(
            versions: versions,
            comparesImageGroups: imageNames.count > 1,
            availabilityPlatform: Self.availabilityPlatform
        )
    }

    /// The axis a pipeline reading `language` runs over. Computed at
    /// initialization: the class properties it derives from are isolated to
    /// the test actor, the pipelines are not.
    nonisolated func versionAxis(for language: MetadataLanguage) -> VersionAxis {
        axes.axis(for: language)
    }
}
