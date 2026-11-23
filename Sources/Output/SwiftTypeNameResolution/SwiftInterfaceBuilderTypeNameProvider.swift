#if os(macOS)

import Foundation
import MachOKit
import MachOKitExtensions
import MachOSwiftSection
import ObjCMetadataSource
import ObjCTypeIndexing
import SwiftInterface
import SwiftPrinting
import TypeIndexing

/// The `SwiftInterfaceBuilder` extra-data provider that resolves `__C` /
/// `__ObjC` types: attach it and `__C.NSString` prints as
/// `Foundation.NSString`, `__C.UICellConfigurationState` as
/// `UIKit.__UICellConfigurationState`, through a swift-type-indexing
/// `TypeDatabase` built for the indexed binary's platform and dependency set.
@available(macOS 13.0, *)
public final class SwiftInterfaceBuilderTypeNameProvider<MachO: MachOSwiftSectionRepresentableWithCache & ObjCMetadataSource & Sendable>: SwiftInterfaceBuilderExtraDataProvider, ModuleNameResolving, CImportedNameResolving, Sendable {
    public let machO: MachO

    private let resolver: TypeDatabaseTypeNameResolver

    private let dependencies: SwiftInterfaceBuilderDependencies<MachO>

    /// Fails when the binary carries no build-version load command mapping to
    /// a known SDK platform — without a platform there is no SDK to index.
    ///
    /// `supplementaryAPINotesURLs` names `.apinotes` files or directories of
    /// user-provided type mappings (evolution proposal 0010), loaded after
    /// the SDK's own APINotes so they overwrite them.
    public init?(machO: MachO, dependencies: SwiftInterfaceBuilderDependencies<MachO>, supplementaryAPINotesURLs: [URL] = []) {
        guard
            let buildPlatform = machO.loadCommands.buildVersionCommand?.platform,
            let platform = SDKPlatform(buildPlatform)
        else {
            return nil
        }
        self.machO = machO
        self.dependencies = dependencies
        self.resolver = TypeDatabaseTypeNameResolver(typeDatabase: TypeDatabase(platform: platform, supplementaryAPINotesURLs: supplementaryAPINotesURLs))
    }

    public func setup() async throws {
        // Index only the SDK modules the binary actually links: the module
        // filter is keyed on the dependency images' module names, which is
        // what makes first-run indexing minutes-of-modules instead of the
        // whole SDK.
        let dependencyImages = dependencies.dependencies
        let dependencyModuleNames = Set(dependencyImages.map { TypeDatabase.moduleName(forImagePath: $0.imagePath) })
        try await resolver.typeDatabase.index(
            dependencies: dependencyImages.map { ObjCDeclaredTypeNames(machO: $0, imagePath: $0.imagePath) },
            moduleFilter: { dependencyModuleNames.contains($0) }
        )
    }

    public func moduleName(forTypeName typeName: String) async -> String? {
        await resolver.moduleName(forTypeName: typeName)
    }

    public func swiftName(forCName cName: String, category: CImportedTypeNameCategory) async -> String? {
        await resolver.swiftName(forCName: cName, category: category)
    }
}

#endif
