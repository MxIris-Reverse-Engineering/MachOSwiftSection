import Foundation
import MachOSwiftSection
import OrderedCollections

// MARK: - ConformanceProvider Protocol

/// Protocol for providing type conformance information
public protocol ConformanceProvider: Sendable {
    /// Find all types that conform to a given protocol
    /// - Parameter protocolName: The protocol to search for conformances
    /// - Returns: Array of type names that conform to the protocol
    func types(conformingTo protocolName: ProtocolName) -> [TypeName]

    /// Check if a type conforms to a protocol
    /// - Parameters:
    ///   - typeName: The type to check
    ///   - protocolName: The protocol to check against
    /// - Returns: True if the type conforms to the protocol
    func doesType(_ typeName: TypeName, conformTo protocolName: ProtocolName) -> Bool

    /// Get all protocols that a type conforms to
    /// - Parameter typeName: The type to query
    /// - Returns: Array of protocol names the type conforms to
    func conformances(of typeName: TypeName) -> [ProtocolName]

    /// Get all indexed type names
    var allTypeNames: [TypeName] { get }

    /// Get type definition if available
    func typeDefinition(for typeName: TypeName) -> TypeDefinition?

    /// Get image path for a type
    func imagePath(for typeName: TypeName) -> String?
}

// MARK: - Default Implementations

extension ConformanceProvider {
    /// Find types that conform to all specified protocols
    public func types(conformingToAll protocols: [ProtocolName]) -> [TypeName] {
        guard let first = protocols.first else { return allTypeNames }

        var result = Set(types(conformingTo: first))
        for proto in protocols.dropFirst() {
            result.formIntersection(types(conformingTo: proto))
        }
        return Array(result)
    }

    /// Check if a type conforms to all specified protocols
    public func doesType(_ typeName: TypeName, conformToAll protocols: [ProtocolName]) -> Bool {
        protocols.allSatisfy { doesType(typeName, conformTo: $0) }
    }
}

// MARK: - IndexerConformanceProvider

/// ConformanceProvider implementation backed by SwiftInterfaceIndexer
///
/// Note: This type is marked as @_spi(Support) because it depends on SwiftInterfaceIndexer
/// which is also SPI. Use the factory method on GenericSpecializer to create instances.
@_spi(Support)
public final class IndexerConformanceProvider<MachO: MachOSwiftSectionRepresentableWithCache>: @unchecked Sendable {
    private let indexer: SwiftInterfaceIndexer<MachO>

    public init(indexer: SwiftInterfaceIndexer<MachO>) {
        self.indexer = indexer
    }
}

@_spi(Support)
extension IndexerConformanceProvider: ConformanceProvider {
    public func types(conformingTo protocolName: ProtocolName) -> [TypeName] {
        (indexer.allConformingTypesByProtocolName[protocolName] ?? []).map(\.value)
    }

    public func doesType(_ typeName: TypeName, conformTo protocolName: ProtocolName) -> Bool {
        indexer.allProtocolConformancesByTypeName[typeName]?[protocolName] != nil
    }

    public func conformances(of typeName: TypeName) -> [ProtocolName] {
        Array(indexer.allProtocolConformancesByTypeName[typeName]?.keys ?? [])
    }

    public var allTypeNames: [TypeName] {
        Array(indexer.allAllTypeDefinitions.keys)
    }

    public func typeDefinition(for typeName: TypeName) -> TypeDefinition? {
        indexer.allAllTypeDefinitions[typeName]?.value
    }

    public func imagePath(for typeName: TypeName) -> String? {
        indexer.allAllTypeDefinitions[typeName]?.machO.imagePath
    }
}

// MARK: - CompositeConformanceProvider

/// ConformanceProvider that combines multiple providers
public struct CompositeConformanceProvider: ConformanceProvider {
    private let providers: [any ConformanceProvider]

    public init(providers: [any ConformanceProvider]) {
        self.providers = providers
    }

    public func types(conformingTo protocolName: ProtocolName) -> [TypeName] {
        var seen = Set<TypeName>()
        var result: [TypeName] = []
        for provider in providers {
            for typeName in provider.types(conformingTo: protocolName) {
                if seen.insert(typeName).inserted {
                    result.append(typeName)
                }
            }
        }
        return result
    }

    public func doesType(_ typeName: TypeName, conformTo protocolName: ProtocolName) -> Bool {
        providers.contains { $0.doesType(typeName, conformTo: protocolName) }
    }

    public func conformances(of typeName: TypeName) -> [ProtocolName] {
        var seen = Set<ProtocolName>()
        var result: [ProtocolName] = []
        for provider in providers {
            for proto in provider.conformances(of: typeName) {
                if seen.insert(proto).inserted {
                    result.append(proto)
                }
            }
        }
        return result
    }

    public var allTypeNames: [TypeName] {
        var seen = Set<TypeName>()
        var result: [TypeName] = []
        for provider in providers {
            for typeName in provider.allTypeNames {
                if seen.insert(typeName).inserted {
                    result.append(typeName)
                }
            }
        }
        return result
    }

    public func typeDefinition(for typeName: TypeName) -> TypeDefinition? {
        for provider in providers {
            if let def = provider.typeDefinition(for: typeName) {
                return def
            }
        }
        return nil
    }

    public func imagePath(for typeName: TypeName) -> String? {
        for provider in providers {
            if let path = provider.imagePath(for: typeName) {
                return path
            }
        }
        return nil
    }
}

// MARK: - EmptyConformanceProvider

/// Empty provider for testing or when no conformance info is available
public struct EmptyConformanceProvider: ConformanceProvider {
    public init() {}

    public func types(conformingTo protocolName: ProtocolName) -> [TypeName] { [] }
    public func doesType(_ typeName: TypeName, conformTo protocolName: ProtocolName) -> Bool { false }
    public func conformances(of typeName: TypeName) -> [ProtocolName] { [] }
    public var allTypeNames: [TypeName] { [] }
    public func typeDefinition(for typeName: TypeName) -> TypeDefinition? { nil }
    public func imagePath(for typeName: TypeName) -> String? { nil }
}

// MARK: - StandardLibraryConformanceProvider

/// Provider for common standard library type conformances
/// This provides a fallback for well-known types when indexer data is not available
public struct StandardLibraryConformanceProvider: ConformanceProvider {
    /// Known conformances: type name -> set of protocol names
    private let knownConformances: [String: Set<String>]

    public init() {
        // Common standard library conformances
        // These are simplified names without module prefix for matching
        self.knownConformances = [
            "Int": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "BitwiseCopyable"],
            "Int8": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "BitwiseCopyable"],
            "Int16": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "BitwiseCopyable"],
            "Int32": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "BitwiseCopyable"],
            "Int64": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "BitwiseCopyable"],
            "UInt": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "BitwiseCopyable"],
            "UInt8": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "BitwiseCopyable"],
            "UInt16": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "BitwiseCopyable"],
            "UInt32": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "BitwiseCopyable"],
            "UInt64": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "BitwiseCopyable"],
            "Float": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "BitwiseCopyable"],
            "Double": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "BitwiseCopyable"],
            "Bool": ["Equatable", "Hashable", "Codable", "Sendable", "BitwiseCopyable"],
            "String": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable", "Collection", "BidirectionalCollection"],
            "Character": ["Equatable", "Hashable", "Comparable", "Sendable"],
            "Array": ["Equatable", "Hashable", "Collection", "MutableCollection", "RandomAccessCollection", "Codable", "Sendable"],
            "Set": ["Equatable", "Hashable", "Collection", "Codable", "Sendable"],
            "Dictionary": ["Equatable", "Collection", "Codable", "Sendable"],
            "Optional": ["Equatable", "Hashable", "Sendable"],
            "Data": ["Equatable", "Hashable", "Collection", "MutableCollection", "RandomAccessCollection", "Codable", "Sendable"],
            "Date": ["Equatable", "Hashable", "Comparable", "Codable", "Sendable"],
            "URL": ["Equatable", "Hashable", "Codable", "Sendable"],
            "UUID": ["Equatable", "Hashable", "Codable", "Sendable"],
        ]
    }

    public func types(conformingTo protocolName: ProtocolName) -> [TypeName] {
        // Standard library provider doesn't return type names
        // It only validates conformances for known types
        []
    }

    public func doesType(_ typeName: TypeName, conformTo protocolName: ProtocolName) -> Bool {
        let simpleName = simplifyTypeName(typeName.name)
        let simpleProto = simplifyTypeName(protocolName.name)
        return knownConformances[simpleName]?.contains(simpleProto) ?? false
    }

    public func conformances(of typeName: TypeName) -> [ProtocolName] {
        // Would need to create ProtocolName instances which requires Node
        // For now, return empty - this provider is mainly for validation
        []
    }

    public var allTypeNames: [TypeName] { [] }

    public func typeDefinition(for typeName: TypeName) -> TypeDefinition? { nil }
    public func imagePath(for typeName: TypeName) -> String? { nil }

    private func simplifyTypeName(_ name: String) -> String {
        // Remove module prefix (e.g., "Swift.Int" -> "Int")
        if let dotIndex = name.lastIndex(of: ".") {
            return String(name[name.index(after: dotIndex)...])
        }
        return name
    }
}
