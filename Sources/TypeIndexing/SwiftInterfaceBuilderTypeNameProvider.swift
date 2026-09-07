#if os(macOS)

import Foundation
import MachOKit
import MachOSwiftSection
import ObjCMetadataSource
import SwiftInterface
import SwiftPrinting

/// The `SwiftInterfaceBuilder` extra-data provider that restores real module
/// names for `__C` / `__ObjC` types: attach it and the printer's
/// `moduleName(forTypeName:)` delegate resolves `__C.NSString` to
/// `Foundation.NSString` through a ``TypeDatabase`` built for the indexed
/// binary's platform and dependency set.
@available(macOS 13.0, *)
public final class SwiftInterfaceBuilderTypeNameProvider<MachO: MachOSwiftSectionRepresentableWithCache & ObjCMetadataSource & Sendable>: SwiftInterfaceBuilderExtraDataProvider, ModuleNameResolving, CImportedNameResolving, Sendable {
    public let machO: MachO

    private let typeDatabase: TypeDatabase<MachO>

    private let dependencies: SwiftInterfaceBuilderDependencies<MachO>

    /// Fails when the binary carries no build-version load command mapping to
    /// a known SDK platform — without a platform there is no SDK to index.
    ///
    /// `supplementaryAPINotesURLs` names `.apinotes` files or directories of
    /// user-provided type mappings (evolution proposal 0010), loaded after
    /// the SDK's own APINotes so they overwrite them.
    public init?(machO: MachO, dependencies: SwiftInterfaceBuilderDependencies<MachO>, supplementaryAPINotesURLs: [URL] = []) {
        guard let platform = machO.loadCommands.buildVersionCommand?.platform.sdkPlatform else {
            return nil
        }
        self.machO = machO
        self.dependencies = dependencies
        self.typeDatabase = TypeDatabase(platform: platform, supplementaryAPINotesURLs: supplementaryAPINotesURLs)
    }

    public func setup() async throws {
        // Index only the SDK modules the binary actually links: the module
        // filter is keyed on the dependency images' module names, which is
        // what makes first-run indexing minutes-of-modules instead of the
        // whole SDK.
        let dependencyModuleNames = Set(dependencies.dependencies.map { TypeDatabase<MachO>.moduleName(forImagePath: $0.imagePath) })
        try await typeDatabase.index(dependencies: dependencies.dependencies) { dependencyModuleNames.contains($0) }
    }

    public func moduleName(forTypeName typeName: String) async -> String? {
        await typeDatabase.moduleName(forTypeName: typeName)
    }

    public func swiftName(forCName cName: String, category: CImportedTypeNameCategory) async -> String? {
        await typeDatabase.swiftName(forCName: cName, category: category)
    }
}

@available(macOS 13.0, *)
extension MachOKit.Platform {
    var sdkPlatform: SDKPlatform? {
        switch self {
        case .macOS,
             .macCatalyst:
            return .macOS
        case .driverKit:
            return .driverKit
        case .iOS:
            return .iOS
        case .tvOS:
            return .tvOS
        case .watchOS:
            return .watchOS
        case .visionOS:
            return .visionOS
        case .iOSSimulator:
            return .iOSSimulator
        case .tvOSSimulator:
            return .tvOSSimulator
        case .watchOSSimulator:
            return .watchOSSimulator
        case .visionOSSimulator:
            return .visionOSSimulator
        default:
            return nil
        }
    }
}

extension LoadCommandsProtocol {
    var buildVersionCommand: BuildVersionCommand? {
        for command in self {
            switch command {
            case .buildVersion(let buildVersionCommand):
                return buildVersionCommand
            default:
                break
            }
        }
        return nil
    }
}

#endif
