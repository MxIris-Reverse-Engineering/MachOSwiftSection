#if os(macOS)

import ObjCMetadataSource
import ObjCTypeIndexing
import TypeIndexing

/// Every type an image declares, as one swift-type-indexing source: the
/// classes, protocols, structs and unions its Objective-C metadata names
/// (`ObjCDeclaredTypeNames`), then the CF types it exports a `GetTypeID`
/// function for (`CFDeclaredTypeNames`).
///
/// `TypeDatabase` keeps one source per image path and skips any later one
/// with the same path, so an image's CF types registered beside its
/// Objective-C names, as a second source, would never be read. Register this
/// instead of the two (evolution proposal `private-cf-type-modules`).
///
/// ```swift
/// let typeDatabase = TypeDatabase(platform: .macOS)
/// try await typeDatabase.index(
///     dependencies: dependencyImages.map { ImageDeclaredTypeNames(machO: $0, imagePath: $0.imagePath) },
///     moduleFilter: { dependencyModuleNames.contains($0) }
/// )
/// ```
public struct ImageDeclaredTypeNames<MachO: ObjCMetadataSource>: DeclaredTypeNameSource {
    public let imagePath: String

    private let objectiveCTypeNames: ObjCDeclaredTypeNames<MachO>

    private let coreFoundationTypeNames: CFDeclaredTypeNames<MachO>

    /// - Parameters:
    ///   - machO: The image, in this process or in a file.
    ///   - imagePath: Its install path, which names the module its types are
    ///     attributed to (`…/IOSurface.framework/Versions/A/IOSurface` →
    ///     `IOSurface`).
    public init(machO: MachO, imagePath: String) {
        self.imagePath = imagePath
        self.objectiveCTypeNames = ObjCDeclaredTypeNames(machO: machO, imagePath: imagePath)
        self.coreFoundationTypeNames = CFDeclaredTypeNames(machO: machO, imagePath: imagePath)
    }

    /// The Objective-C names, then the CF typedef names. Throws when the
    /// Objective-C metadata cannot be read, as `ObjCDeclaredTypeNames` does on
    /// its own: `TypeDatabase` then logs the image and skips it whole.
    public func declaredTypeNames() async throws -> [String] {
        let objectiveCNames = try await objectiveCTypeNames.declaredTypeNames()
        let typedefNames = await coreFoundationTypeNames.declaredTypeNames()
        return objectiveCNames + typedefNames
    }
}

#endif
