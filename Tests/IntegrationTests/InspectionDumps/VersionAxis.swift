import Foundation
import MachOKit
@testable import MachOSwiftSection

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
