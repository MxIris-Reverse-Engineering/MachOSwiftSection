import Foundation
import MachOSwiftSection
import OrderedCollections
import Demangling
@_spi(Internals) import SwiftInspection

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

    /// Returns `baseClassName` together with every direct or transitive
    /// subclass of it that the provider knows about. The base class itself
    /// is always the first element when the provider recognises it (the
    /// `T: T` case trivially satisfies `T: BaseClass`); an empty result
    /// means the provider has no information about this type, not that it
    /// has no subclasses.
    ///
    /// Used by `findCandidates` to narrow `<A: BaseClass>` candidate
    /// lists. Default implementation returns `[]`, so providers that have
    /// no class-hierarchy knowledge degrade to "show every candidate"
    /// without breaking the contract.
    func subclasses(of baseClassName: TypeName) -> [TypeName]
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

    /// Default conservative implementation — providers that do not index
    /// class hierarchy information return an empty list, signalling
    /// "unknown" rather than "no subclasses". `findCandidates` interprets
    /// the empty result as "do not narrow", keeping the existing
    /// "show every candidate" behaviour for non-indexer providers.
    public func subclasses(of baseClassName: TypeName) -> [TypeName] {
        []
    }
}

// MARK: - IndexerConformanceProvider

/// ConformanceProvider implementation backed by SwiftInterfaceIndexer.
///
/// **Preparation contract.** The wrapped `SwiftInterfaceIndexer` must have
/// completed `prepare()` before this provider is queried — `findCandidates`
/// reads `allConformingTypesByProtocolName` / `allAllTypeDefinitions`, which
/// the indexer populates lazily during preparation. The class is marked
/// `@unchecked Sendable` to keep the API ergonomic when stored on a long-
/// lived `GenericSpecializer`, but it does *not* protect against concurrent
/// reads while preparation is still mutating the indexer's storage; callers
/// must order `await indexer.prepare()` before passing the indexer here.
///
/// Note: This type is marked as `@_spi(Support)` because it depends on
/// `SwiftInterfaceIndexer`, which is also SPI. Use the factory initializer
/// on `GenericSpecializer` to create instances.
@_spi(Support)
public final class IndexerConformanceProvider<MachO: MachOSwiftSectionRepresentableWithCache>: @unchecked Sendable {
    private let indexer: SwiftInterfaceIndexer<MachO>

    /// Lazy cache: superclass canonical-name string → array of direct
    /// subclass `TypeName`s. Keyed by `TypeName.name` rather than the
    /// `TypeName` itself because demangling the same class through two
    /// different mangled-name sources (parameter constraint RHS vs. a
    /// child class's `superclassType` link) can produce nominally
    /// equivalent `Node` trees that hash differently — e.g. when one
    /// side resolves a symbolic reference and the other doesn't, or
    /// when caches keep distinct `Node` instances. The print string
    /// (`TypeName.name`, "Module.Type") is stable across both paths.
    private final class SubclassCache: @unchecked Sendable {
        var directChildrenByParentName: [String: [TypeName]]?
        let lock = NSLock()
    }

    private let subclassCache = SubclassCache()

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

    public func subclasses(of baseClassName: TypeName) -> [TypeName] {
        // baseClass requirement is irrelevant for non-class subjects —
        // return empty so callers can fall back to "do not narrow".
        guard baseClassName.kind == .class else { return [] }

        let directChildren = directChildrenMap()

        // BFS over the parent → direct-subclasses graph, keyed by
        // canonical name string. Result list still uses `TypeName`s
        // (preserving the public API) — the string indirection is
        // internal to the cache.
        var result: [TypeName] = [baseClassName]
        var seenNames: Set<String> = [baseClassName.name]
        var queueNames: [String] = [baseClassName.name]
        while !queueNames.isEmpty {
            let current = queueNames.removeFirst()
            for child in directChildren[current] ?? [] {
                if seenNames.insert(child.name).inserted {
                    result.append(child)
                    queueNames.append(child.name)
                }
            }
        }
        return result
    }

    /// Build (or fetch from cache) the parent-name → direct-subclasses
    /// map by walking every indexed `.class` definition's
    /// `superclassType` link. Lock-protected so concurrent first-callers
    /// don't both pay the O(n) build cost.
    private func directChildrenMap() -> [String: [TypeName]] {
        subclassCache.lock.lock()
        defer { subclassCache.lock.unlock() }
        if let cached = subclassCache.directChildrenByParentName { return cached }

        var map: [String: [TypeName]] = [:]
        for (childTypeName, entry) in indexer.allAllTypeDefinitions {
            guard childTypeName.kind == .class else { continue }
            guard case .class(let classWrapper) = entry.value.type else { continue }

            var superNode: Node?
            do {
                superNode = try classWrapper.superclassNode(in: entry.machO)
            } catch {
                continue
            }
            guard let superNode else { continue }

            // `MetadataReader.demangleType` may wrap the result in a
            // `.type` node or return a deeper tree depending on the
            // mangled shape. `.first(of: .type)` mirrors how
            // `SwiftInterfaceIndexer` itself extracts the type node when
            // it indexes extensions/protocol conformances.
            //
            // Kind is hardcoded `.class` rather than derived from
            // `Node.typeKind` for the same reason as
            // `baseClassConstraintTypeName`: that helper mis-tags a
            // class nested inside a struct as `.struct`. A
            // `superclassType` link is class-by-construction (the
            // `superclassTypeMangledName` ABI slot only exists on
            // class descriptors), so we can commit to `.class`
            // unconditionally.
            guard let superNode = superNode.first(of: .type) else {
                continue
            }
            let superTypeName = TypeName(node: superNode, kind: .class)
            map[superTypeName.name, default: []].append(childTypeName)
        }

        subclassCache.directChildrenByParentName = map
        return map
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

    public func subclasses(of baseClassName: TypeName) -> [TypeName] {
        // Merge subclass lists from every provider; dedupe across them
        // (a class may legitimately surface in multiple sub-indexers when
        // images overlap or conformances are restated).
        var seen = Set<TypeName>()
        var result: [TypeName] = []
        for provider in providers {
            for subclass in provider.subclasses(of: baseClassName) {
                if seen.insert(subclass).inserted {
                    result.append(subclass)
                }
            }
        }
        return result
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
