import Foundation
import Testing
import MachOKit
import SwiftSectionFixtureSupport
import SwiftSectionTestingSupport
@testable import MachOSwiftSection
import ObjCMetadataSource
import ObjCIndexing
import ObjCInterface
import ObjCDiffing

/// The platform a version axis spells availability for — what
/// `evolution --interface --emit-available --platform` passes — each
/// pipeline in its own spelling.
enum AvailabilityPlatform: Sendable {
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

/// One image of one version on a version axis.
struct AxisImage: Sendable {
    let imageName: String
    let machOFile: MachOFile
}

/// One version on a version axis: its label and the images whose
/// declarations make it up, the primary image first.
struct AxisVersion: Sendable {
    let label: String
    let images: [AxisImage]

    var primaryImage: AxisImage { images[0] }

    /// This version as a pipeline reading `language` sees it: only the
    /// images carrying that metadata, or `nil` — off the axis — when the
    /// primary image does not.
    func keepingImages(carrying language: MetadataLanguage) -> AxisVersion? {
        guard language.isCarried(by: primaryImage.machOFile) else { return nil }
        return AxisVersion(label: label, images: images.filter { language.isCarried(by: $0.machOFile) })
    }
}

/// One ordered series of versions (oldest first), as one pipeline reads it:
/// a diff reads its first and last version, an evolution every version.
struct VersionAxis: Sendable {
    let versions: [AxisVersion]
    /// Whether every version is a group of images (evolution proposal
    /// `image-group-evolution`). It picks the evolution builders'
    /// image-group entry points, which name each version's images and
    /// record moves between them, so a version of one image still reads
    /// differently from a group of one.
    let comparesImageGroups: Bool
    /// Set when every label is a version number, so the evolution
    /// interfaces also spell each lifecycle one attribute or macro can
    /// express.
    let availabilityPlatform: AvailabilityPlatform?
}

/// The axis of each metadata language over one series of versions: each
/// keeps the versions whose primary image carries that language's metadata.
struct VersionAxes: Sendable {
    private let swiftAxis: VersionAxis
    private let objcAxis: VersionAxis

    init(versions: [AxisVersion], comparesImageGroups: Bool, availabilityPlatform: AvailabilityPlatform?) {
        self.swiftAxis = VersionAxis(
            versions: versions.compactMap { $0.keepingImages(carrying: .swift) },
            comparesImageGroups: comparesImageGroups,
            availabilityPlatform: availabilityPlatform
        )
        self.objcAxis = VersionAxis(
            versions: versions.compactMap { $0.keepingImages(carrying: .objc) },
            comparesImageGroups: comparesImageGroups,
            availabilityPlatform: availabilityPlatform
        )
    }

    func axis(for language: MetadataLanguage) -> VersionAxis {
        switch language {
        case .swift: swiftAxis
        case .objc: objcAxis
        }
    }
}

/// A dump over an ordered series of versions — a diff or an evolution. A
/// conforming suite supplies the axis each pipeline runs over, usually by
/// inheriting one of the axis base classes below.
protocol VersionAxisDumpTests: InspectionDumpTests {
    func versionAxis(for language: MetadataLanguage) -> VersionAxis
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
extension VersionAxisDumpTests {
    /// One image indexed the way `swift-section objc snapshot` indexes it and
    /// frozen into a labeled snapshot document, round-tripped through the
    /// persisted form: what a diff or an evolution consumes is exactly what a
    /// saved baseline would decode to.
    func objcSnapshotDocument(of image: AxisImage, label: String) async throws -> ObjCAPISnapshotDocument {
        let indexer = try await preparedObjCIndexer(of: image.machOFile)
        let document = ObjCAPISnapshotDocument(
            provenance: ObjCAPIProvenance(
                label: label,
                binaryPath: image.machOFile.imagePath,
                generatorVersion: "IntegrationTests",
                createdAt: Date()
            ),
            snapshot: ObjCAPISnapshotBuilder(indexer: indexer).snapshot()
        )
        return try ObjCAPISnapshotDocument.decode(from: document.encoded())
    }
}

/// Extracts the same images from an *ordered series* of dyld shared caches:
/// N versions for an evolution, two for a diff. The caches are retained
/// because the extracted `MachOFile`s resolve cross-image references through
/// them while indexing.
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
/// caches from 13.0 on, SwiftUICore from 15.0 on. A diff reads the primary
/// image of each version only.
@TestActor
class MultiVersionDyldCacheImageTests: Sendable {
    let caches: [FullDyldCache]
    private let axes: VersionAxes

    /// Oldest first; each cache's `versionLabel` labels it on the axis.
    class var cachePaths: [DyldSharedCachePath] { defaultMacOSCachePaths }

    class var cacheImageName: MachOImageName { .SwiftUI }

    /// The images whose declarations make up one version, the primary
    /// image first; by default the primary image alone.
    class var cacheImageNames: [MachOImageName] { [cacheImageName] }

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
        let primaryImageName = Self.cacheImageNames.first?.name
        var caches: [FullDyldCache] = []
        var versions: [AxisVersion] = []
        for cachePath in Self.cachePaths {
            let cache = try FullDyldCache(path: cachePath)
            let images = Self.cacheImageNames.compactMap { imageName -> AxisImage? in
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
            comparesImageGroups: Self.cacheImageNames.count > 1,
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

/// The same file from two simulator runtimes, by fixture name — the
/// two-version counterpart of `SwiftSectionTestingSupport.MachOFileTests`,
/// which loads one.
@TestActor
class CrossVersionMachOFileTests: Sendable {
    let oldMachOFile: MachOFile
    let newMachOFile: MachOFile
    private let axes: VersionAxes

    class var oldFileName: MachOFileName { .iOS_18_5_Simulator_SwiftUICore }
    class var newFileName: MachOFileName { .iOS_26_5_Simulator_SwiftUICore }

    /// The runtime versions the two files come from, which label them on the axis.
    class var oldVersionLabel: String { "18.5" }
    class var newVersionLabel: String { "26.5" }

    init() async throws {
        let oldMachOFile = try HostSlice.machOFile(in: loadFromFile(named: Self.oldFileName))
        let newMachOFile = try HostSlice.machOFile(in: loadFromFile(named: Self.newFileName))
        self.oldMachOFile = oldMachOFile
        self.newMachOFile = newMachOFile
        self.axes = VersionAxes(
            versions: [
                AxisVersion(label: Self.oldVersionLabel, images: [AxisImage(imageName: oldMachOFile.imagePath.lastPathComponent, machOFile: oldMachOFile)]),
                AxisVersion(label: Self.newVersionLabel, images: [AxisImage(imageName: newMachOFile.imagePath.lastPathComponent, machOFile: newMachOFile)]),
            ],
            comparesImageGroups: false,
            availabilityPlatform: nil
        )
    }

    nonisolated func versionAxis(for language: MetadataLanguage) -> VersionAxis {
        axes.axis(for: language)
    }
}

/// The same shared framework from two installed Xcode applications, picked
/// by version: `/Applications/Xcode-<version>.app`. The shared
/// `XcodeMachOFileName` fixture names a single Xcode, so this loads by path.
@TestActor
class CrossVersionXcodeFrameworkTests: Sendable {
    let oldMachOFile: MachOFile
    let newMachOFile: MachOFile
    private let axes: VersionAxes

    /// The two Xcode versions, which also label them on the axis.
    class var oldXcodeVersion: String { "26.3.0" }
    class var newXcodeVersion: String { "26.4.0" }
    class var sharedFrameworkName: String { "DVTProductsUI" }

    init() async throws {
        let oldMachOFile = try Self.loadSharedFramework(fromXcodeVersion: Self.oldXcodeVersion)
        let newMachOFile = try Self.loadSharedFramework(fromXcodeVersion: Self.newXcodeVersion)
        self.oldMachOFile = oldMachOFile
        self.newMachOFile = newMachOFile
        let imageName = Self.sharedFrameworkName
        self.axes = VersionAxes(
            versions: [
                AxisVersion(label: Self.oldXcodeVersion, images: [AxisImage(imageName: imageName, machOFile: oldMachOFile)]),
                AxisVersion(label: Self.newXcodeVersion, images: [AxisImage(imageName: imageName, machOFile: newMachOFile)]),
            ],
            comparesImageGroups: false,
            availabilityPlatform: nil
        )
    }

    nonisolated func versionAxis(for language: MetadataLanguage) -> VersionAxis {
        axes.axis(for: language)
    }

    private class func loadSharedFramework(fromXcodeVersion xcodeVersion: String) throws -> MachOFile {
        let name = sharedFrameworkName
        let binaryPath = "/Applications/Xcode-\(xcodeVersion).app/Contents/SharedFrameworks/\(name).framework/Versions/A/\(name)"
        return try HostSlice.machOFile(at: URL(fileURLWithPath: binaryPath))
    }
}
