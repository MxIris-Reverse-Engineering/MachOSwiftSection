import Foundation
@_spi(Internals) import Demangling
import MachOKit
import MachOFoundation

/// What a wrapper type's `wrappedValue` accessor symbols say about it.
public struct PropertyWrapperEvidence: Sendable {
    /// The `wrappedValue` property's type as declared on the wrapper, generic
    /// parameters unsubstituted (`A` for `State<A>`), or `nil` when the
    /// accessor symbol did not demangle to a variable.
    public let wrappedValueTypeNode: Node?

    /// Whether `wrappedValue` has a `set` or `modify` accessor, which is
    /// what decides whether the wrapped property is settable.
    public let hasSetter: Bool

    public init(wrappedValueTypeNode: Node?, hasSetter: Bool) {
        self.wrappedValueTypeNode = wrappedValueTypeNode
        self.hasSetter = hasSetter
    }
}

/// The accessor forms a `wrappedValue` symbol takes, read off its demangled
/// tree (`global → getter | setter | modifyAccessor → variable → type`).
public enum WrappedValueAccessorSymbol {
    public struct Shape: Sendable {
        public let isSetter: Bool
        public let typeNode: Node?
    }

    /// `nil` when `symbolNode` is not an accessor of a variable named
    /// `wrappedValue`.
    public static func shape(of symbolNode: Node) -> Shape? {
        var node = symbolNode
        var isSetter = false
        for _ in 0 ..< 4 where node.kind != .variable {
            switch node.kind {
            case .global:
                guard let next = node.firstChild else { return nil }
                node = next
            case .getter, .static:
                guard let next = node.firstChild else { return nil }
                node = next
            case .setter, .modifyAccessor:
                isSetter = true
                guard let next = node.firstChild else { return nil }
                node = next
            default:
                return nil
            }
        }
        guard node.kind == .variable, node.children.first(where: { $0.kind == .identifier })?.text == "wrappedValue" else { return nil }
        return Shape(isSetter: isSetter, typeNode: node.children.first(where: { $0.kind == .type }))
    }
}

/// Answers "is this nominal type a property wrapper" for one image from the
/// export tries the image can see — its own and its dependency closure's —
/// without demangling anything but the hits: a wrapper exports the accessors
/// of its `wrappedValue` (`$s7SwiftUI5StateV12wrappedValuexvM` and friends),
/// and the export trie is searched by the wrapper's mangled context prefix.
/// This is the cross-image half of wrapped-property recovery; the image's
/// own symbol index (which also knows internal wrappers) is consulted first
/// by `TypeDefinition`, and this catalog is the fallback for a wrapper
/// defined elsewhere (SwiftUI's `@State` used in an app). The dependency
/// closure is built once, on the first cross-image lookup, and every verdict
/// is memoized by prefix.
///
/// A catalog is built per image by `PropertyWrapperTypeCatalogStore` — the
/// indexer registers one with its configured search paths when it prepares,
/// and an image nobody prepared gets one over the system dyld shared cache.
public final class PropertyWrapperTypeCatalog: @unchecked Sendable {
    /// The exported symbol names starting with a prefix, for one image.
    public typealias ExportedSymbolNamesLookup = @Sendable (_ prefix: String) -> [String]

    private let rootLookup: ExportedSymbolNamesLookup?
    private let makeDependencyLookups: @Sendable () -> [ExportedSymbolNamesLookup]
    private let lock = NSLock()
    private var dependencyLookups: [ExportedSymbolNamesLookup]?
    private var memoizedEvidenceByPrefix: [String: PropertyWrapperEvidence?] = [:]

    public init(rootLookup: ExportedSymbolNamesLookup?, dependencyLookups: @escaping @Sendable () -> [ExportedSymbolNamesLookup]) {
        self.rootLookup = rootLookup
        self.makeDependencyLookups = dependencyLookups
    }

    /// A catalog over `root`'s export trie and, on demand, its dependency
    /// closure — resolved through `searchPaths` for a file, through the
    /// loaded images for an in-process image. The reader kinds are a closed
    /// set of two; any other reader gets a catalog that answers nothing.
    public static func make(root: some MachORepresentableWithCache, searchPaths: [DependencySearchPath]) -> PropertyWrapperTypeCatalog {
        if let machOFile = root as? MachOFile {
            return PropertyWrapperTypeCatalog(rootLookup: lookup(for: machOFile)) {
                DependencyClosure(root: machOFile, searchPaths: searchPaths).images.map(lookup(for:))
            }
        }
        if let machOImage = root as? MachOImage {
            return PropertyWrapperTypeCatalog(rootLookup: lookup(for: machOImage)) {
                DependencyClosure(root: machOImage).images.map(lookup(for:))
            }
        }
        return PropertyWrapperTypeCatalog(rootLookup: nil) { [] }
    }

    private static func lookup(for machOFile: MachOFile) -> ExportedSymbolNamesLookup {
        { prefix in machOFile.exportTrie?.search(byKeyPrefix: prefix).map(\.name) ?? [] }
    }

    private static func lookup(for machOImage: MachOImage) -> ExportedSymbolNamesLookup {
        { prefix in machOImage.exportTrie?.search(byKeyPrefix: prefix).map(\.name) ?? [] }
    }

    /// The mangled prefix every `wrappedValue` accessor of `nominalTypeNode`
    /// starts with (`_$s7SwiftUI5StateV12wrappedValue`), or `nil` when the
    /// node does not remangle.
    public static func wrappedValueSymbolPrefix(of nominalTypeNode: Node) -> String? {
        guard var mangled = try? mangleAsString(nominalTypeNode) else { return nil }
        if mangled.hasPrefix("_") { mangled.removeFirst() }
        if mangled.hasPrefix("$s") { mangled.removeFirst(2) }
        return "_$s" + mangled + "12wrappedValue"
    }

    /// The evidence for `nominalTypeNode` being a property wrapper: the
    /// root image's exports first, then the dependency closure's in
    /// resolution order, stopping at the first image exporting a
    /// `wrappedValue` accessor of the type. `nil` when none does.
    public func evidence(forWrapperCandidate nominalTypeNode: Node) -> PropertyWrapperEvidence? {
        guard let prefix = Self.wrappedValueSymbolPrefix(of: nominalTypeNode) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let memoized = memoizedEvidenceByPrefix[prefix] {
            return memoized
        }
        var evidence: PropertyWrapperEvidence?
        if let rootLookup {
            evidence = Self.evidence(fromExportedSymbolNames: rootLookup(prefix))
        }
        if evidence == nil {
            if dependencyLookups == nil {
                dependencyLookups = makeDependencyLookups()
            }
            for dependencyLookup in dependencyLookups ?? [] {
                if let found = Self.evidence(fromExportedSymbolNames: dependencyLookup(prefix)) {
                    evidence = found
                    break
                }
            }
        }
        memoizedEvidenceByPrefix[prefix] = evidence
        return evidence
    }

    /// Folds the accessor symbols found under one prefix into evidence:
    /// the getter (or, failing that, any accessor) supplies the declared
    /// type, a setter or modify accessor makes the property settable.
    public static func evidence(fromExportedSymbolNames names: [String]) -> PropertyWrapperEvidence? {
        var wrappedValueTypeNode: Node?
        var hasSetter = false
        var matched = false
        for name in names {
            let mangled = name.hasPrefix("_") ? String(name.dropFirst()) : name
            guard let symbolNode = try? demangleAsNodeTransient(mangled),
                  let shape = WrappedValueAccessorSymbol.shape(of: symbolNode)
            else { continue }
            matched = true
            hasSetter = hasSetter || shape.isSetter
            if wrappedValueTypeNode == nil, let typeNode = shape.typeNode {
                wrappedValueTypeNode = typeNode
            }
        }
        guard matched else { return nil }
        return PropertyWrapperEvidence(wrappedValueTypeNode: wrappedValueTypeNode, hasSetter: hasSetter)
    }
}

/// The per-image registry of catalogs. Keyed by the image's identifier, the
/// same key the symbol index store uses, so an indexer's registration and
/// eviction line up with its other per-image caches.
public final class PropertyWrapperTypeCatalogStore: @unchecked Sendable {
    public static let shared = PropertyWrapperTypeCatalogStore()

    private let lock = NSLock()
    private var catalogsByImageIdentifier: [AnyHashable: PropertyWrapperTypeCatalog] = [:]

    private init() {}

    /// Installs the catalog an indexer built with its configured search
    /// paths, replacing any default one a lookup created before it.
    public func register(_ catalog: PropertyWrapperTypeCatalog, for machO: some MachORepresentableWithCache) {
        lock.lock()
        defer { lock.unlock() }
        catalogsByImageIdentifier[AnyHashable(machO.identifier)] = catalog
    }

    /// The image's catalog — the registered one, or a default over the
    /// system dyld shared cache created on first use.
    public func catalog(for machO: some MachORepresentableWithCache) -> PropertyWrapperTypeCatalog {
        lock.lock()
        defer { lock.unlock() }
        let key = AnyHashable(machO.identifier)
        if let existing = catalogsByImageIdentifier[key] {
            return existing
        }
        let catalog = PropertyWrapperTypeCatalog.make(root: machO, searchPaths: [.systemDyldSharedCache])
        catalogsByImageIdentifier[key] = catalog
        return catalog
    }

    public func contains(in machO: some MachORepresentableWithCache) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return catalogsByImageIdentifier[AnyHashable(machO.identifier)] != nil
    }

    public func remove(for machO: some MachORepresentableWithCache) {
        lock.lock()
        defer { lock.unlock() }
        catalogsByImageIdentifier[AnyHashable(machO.identifier)] = nil
    }
}
