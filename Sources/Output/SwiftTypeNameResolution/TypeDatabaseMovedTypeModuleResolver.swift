#if os(macOS)

import Foundation
import MachOKit
import SwiftPrinting
import TypeIndexing

/// Answers the printer's question about a Swift type the SDK moved between
/// modules (`@_originallyDefinedIn`) from a swift-type-indexing
/// `TypeDatabase`: `CoreGraphics.CGFloat` prints as `CoreFoundation.CGFloat`,
/// and for an image built with the macOS 15 SDK or later `SwiftUI.View` as
/// `SwiftUICore.View` (evolution proposal `moved-swift-type-modules`).
///
/// `sdkVersion` is the version of the SDK the printed image was built with —
/// its `LC_BUILD_VERSION`'s `sdk` — so an image built before a move keeps the
/// module its SDK declared the type in: the macOS 14 SwiftUI declares `View`
/// itself. The database must be built for the image's platform and indexed
/// (`index(dependencies:moduleFilter:)`, which a filter selecting no module
/// satisfies).
///
/// Register it on a `SwiftDeclarationPrinter` with `addTypeNameResolver(_:)`.
@available(macOS 13.0, *)
public struct TypeDatabaseMovedTypeModuleResolver: MovedTypeModuleResolving {
    public let typeDatabase: TypeDatabase

    /// The SDK version the printed image was built with.
    public let sdkVersion: OperatingSystemVersion

    public init(typeDatabase: TypeDatabase, sdkVersion: OperatingSystemVersion) {
        self.typeDatabase = typeDatabase
        self.sdkVersion = sdkVersion
    }

    public func declaringModuleName(ofMovedTypeNamed typeName: String, originallyDefinedIn originalModuleName: String) async -> String? {
        await typeDatabase.declaringModuleName(ofMovedTypeNamed: typeName, originallyDefinedIn: originalModuleName, builtAgainst: sdkVersion)
    }
}

extension OperatingSystemVersion {
    /// A version a Mach-O load command records (`LC_BUILD_VERSION`'s `sdk`
    /// or `minos`).
    init(machOVersion: MachOKit.Version) {
        self.init(majorVersion: machOVersion.major, minorVersion: machOVersion.minor, patchVersion: machOVersion.patch)
    }
}

#endif
