#if os(macOS)

import MachOKit
import SwiftPrinting
import TypeIndexing

/// Answers the printer's questions about `__C` types from a swift-type-indexing
/// `TypeDatabase`: which module declares a type (`__C.UITraitCollection` →
/// `UIKit.UITraitCollection`) and what Swift calls it
/// (`__C.UICellConfigurationState` → `UIKit.__UICellConfigurationState`).
///
/// Register it on a `SwiftDeclarationPrinter` with `addTypeNameResolver(_:)`.
/// Several printers may share one database: the database is an actor, and a
/// resolver holds nothing else.
///
/// ```swift
/// let typeDatabase = TypeDatabase(platform: .macCatalyst)
/// try await typeDatabase.index(dependencies: [], moduleFilter: { $0 == "UIKit" })
/// printer.addTypeNameResolver(TypeDatabaseTypeNameResolver(typeDatabase: typeDatabase))
/// ```
@available(macOS 13.0, *)
public struct TypeDatabaseTypeNameResolver: ModuleNameResolving, CImportedNameResolving {
    public let typeDatabase: TypeDatabase

    public init(typeDatabase: TypeDatabase) {
        self.typeDatabase = typeDatabase
    }

    public func moduleName(forTypeName typeName: String) async -> String? {
        await typeDatabase.moduleName(forTypeName: typeName)
    }

    public func swiftName(forCName cName: String, category: CImportedTypeNameCategory) async -> String? {
        await typeDatabase.swiftName(forCName: cName, category: ImportedTypeNameCategory(category))
    }
}

extension ImportedTypeNameCategory {
    /// The category swift-type-indexing looks a name up in for the printer's
    /// category of a reference. The two enumerate the same namespaces.
    public init(_ printerCategory: CImportedTypeNameCategory) {
        switch printerCategory {
        case .objcClass:
            self = .objcClass
        case .objcProtocol:
            self = .objcProtocol
        case .valueType:
            self = .valueType
        case .other:
            self = .other
        }
    }
}

extension SDKPlatform {
    /// The SDK an image built for `platform` is read against, or `nil` for a
    /// platform no SDK covers. Mac Catalyst has its own case: its frameworks
    /// and API notes are the macOS SDK's `System/iOSSupport` ones.
    public init?(_ platform: MachOKit.Platform) {
        switch platform {
        case .macOS:
            self = .macOS
        case .macCatalyst:
            self = .macCatalyst
        case .driverKit:
            self = .driverKit
        case .iOS:
            self = .iOS
        case .tvOS:
            self = .tvOS
        case .watchOS:
            self = .watchOS
        case .visionOS:
            self = .visionOS
        case .iOSSimulator:
            self = .iOSSimulator
        case .tvOSSimulator:
            self = .tvOSSimulator
        case .watchOSSimulator:
            self = .watchOSSimulator
        case .visionOSSimulator:
            self = .visionOSSimulator
        default:
            return nil
        }
    }
}

#endif
