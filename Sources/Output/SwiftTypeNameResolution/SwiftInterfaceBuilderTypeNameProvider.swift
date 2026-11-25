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

/// What a `SwiftInterfaceBuilderTypeNameProvider` resolves through the SDK.
@available(macOS 13.0, *)
public struct SDKTypeNameResolutions: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// `__C` / `__ObjC` types: the module that declares them and the name
    /// Swift gives them (`__C.NSString` → `Foundation.NSString`). Indexes the
    /// SDK modules the binary links through sourcekitd — the first run per
    /// SDK generates their interfaces.
    public static let cImportedModules = SDKTypeNameResolutions(rawValue: 1 << 0)

    /// Swift types the SDK moved between modules (`@_originallyDefinedIn`):
    /// the module that declares them now (`CoreGraphics.CGFloat` →
    /// `CoreFoundation.CGFloat`), for the SDK version the binary was built
    /// with. Reads the SDK's textual interfaces; no sourcekitd.
    public static let movedTypeModules = SDKTypeNameResolutions(rawValue: 1 << 1)
}

/// The `SwiftInterfaceBuilder` extra-data provider that resolves type names
/// through the SDK the indexed binary was built for: attach it and
/// `__C.NSString` prints as `Foundation.NSString`,
/// `__C.UICellConfigurationState` as `UIKit.__UICellConfigurationState`, and —
/// with ``SDKTypeNameResolutions/movedTypeModules`` — `CoreGraphics.CGFloat` as
/// `CoreFoundation.CGFloat`, through one swift-type-indexing `TypeDatabase`
/// built for the binary's platform and dependency set.
@available(macOS 13.0, *)
public final class SwiftInterfaceBuilderTypeNameProvider<MachO: MachOSwiftSectionRepresentableWithCache & ObjCMetadataSource & Sendable>: SwiftInterfaceBuilderExtraDataProvider, ModuleNameResolving, CImportedNameResolving, MovedTypeModuleResolving, Sendable {
    public let machO: MachO

    /// What this provider resolves; a role it was not asked for answers
    /// `nil`.
    public let resolutions: SDKTypeNameResolutions

    private let resolver: TypeDatabaseTypeNameResolver

    /// `nil` unless ``resolutions`` contains
    /// ``SDKTypeNameResolutions/movedTypeModules``.
    private let movedTypeModuleResolver: TypeDatabaseMovedTypeModuleResolver?

    private let dependencies: SwiftInterfaceBuilderDependencies<MachO>

    /// Fails when the binary carries no build-version load command mapping to
    /// a known SDK platform — without a platform there is no SDK to index.
    ///
    /// `supplementaryAPINotesURLs` names `.apinotes` files or directories of
    /// user-provided type mappings (evolution proposal 0010), loaded after
    /// the SDK's own APINotes so they overwrite them.
    public init?(machO: MachO, dependencies: SwiftInterfaceBuilderDependencies<MachO>, resolutions: SDKTypeNameResolutions = .cImportedModules, supplementaryAPINotesURLs: [URL] = []) {
        guard
            let buildVersionCommand = machO.loadCommands.buildVersionCommand,
            let platform = SDKPlatform(buildVersionCommand.platform)
        else {
            return nil
        }
        self.machO = machO
        self.resolutions = resolutions
        self.dependencies = dependencies
        let typeDatabase = TypeDatabase(platform: platform, supplementaryAPINotesURLs: supplementaryAPINotesURLs)
        self.resolver = TypeDatabaseTypeNameResolver(typeDatabase: typeDatabase)
        self.movedTypeModuleResolver = resolutions.contains(.movedTypeModules)
            ? TypeDatabaseMovedTypeModuleResolver(typeDatabase: typeDatabase, sdkVersion: OperatingSystemVersion(machOVersion: buildVersionCommand.sdk))
            : nil
    }

    public func setup() async throws {
        guard resolutions.contains(.cImportedModules) else {
            // Moved types come from the SDK discovery alone: a filter
            // selecting no module generates no interface.
            try await resolver.typeDatabase.index(dependencies: [], moduleFilter: { _ in false })
            return
        }
        // Index only the SDK modules the binary actually links: the module
        // filter is keyed on the dependency images' module names, which is
        // what makes first-run indexing minutes-of-modules instead of the
        // whole SDK.
        let dependencyImages = dependencies.dependencies
        let dependencyModuleNames = Set(dependencyImages.map { TypeDatabase.moduleName(forImagePath: $0.imagePath) })
        try await resolver.typeDatabase.index(
            dependencies: Self.declaredTypeNameSources(root: machO, dependencies: dependencyImages),
            moduleFilter: { dependencyModuleNames.contains($0) }
        )
    }

    /// The images' own lists of the types they declare, in the order
    /// `TypeDatabase` reads them on a name the SDK does not attribute: the
    /// root's CF types first — a type the root defines is its own — then each
    /// direct dependency's Objective-C names and CF types, in dependency
    /// order. The root generates no SDK interface: it is not in the module
    /// filter.
    static func declaredTypeNameSources(root: MachO, dependencies: [MachO]) -> [any DeclaredTypeNameSource] {
        var sources: [any DeclaredTypeNameSource] = [CFDeclaredTypeNames(machO: root, imagePath: root.imagePath)]
        for dependency in dependencies {
            sources.append(ObjCDeclaredTypeNames(machO: dependency, imagePath: dependency.imagePath))
            sources.append(CFDeclaredTypeNames(machO: dependency, imagePath: dependency.imagePath))
        }
        return sources
    }

    public func moduleName(forTypeName typeName: String) async -> String? {
        guard resolutions.contains(.cImportedModules) else { return nil }
        return await resolver.moduleName(forTypeName: typeName)
    }

    public func swiftName(forCName cName: String, category: CImportedTypeNameCategory) async -> String? {
        guard resolutions.contains(.cImportedModules) else { return nil }
        return await resolver.swiftName(forCName: cName, category: category)
    }

    public func declaringModuleName(ofMovedTypeNamed typeName: String, originallyDefinedIn originalModuleName: String) async -> String? {
        await movedTypeModuleResolver?.declaringModuleName(ofMovedTypeNamed: typeName, originallyDefinedIn: originalModuleName)
    }
}

#endif
