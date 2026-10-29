import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
@_spi(Internals) import SwiftInspection
import Demangling

/// A Swift type, as a type query looks for it.
public struct SwiftTypeIdentity: Hashable, Sendable {
    /// The type's nominal mangling, without `$s` or a suffix:
    /// `7SwiftUI4TextV`, `Sa`, `So6CGRectV`.
    public let key: String
    /// Where the type's context descriptor lies.
    public let descriptorLocation: CodeLocation
    /// For a Swift class: its class object's runtime name and where it lies.
    /// Code reaches the class through its Objective-C class object as well.
    public let objectiveCClassName: String?
    public let objectiveCClassLocation: CodeLocation?
}

extension CrossReferenceAnalyzer {
    /// The type whose context descriptor lies at `location`.
    public func swiftTypeIdentity(ofDescriptorAt location: CodeLocation) -> SwiftTypeIdentity? {
        guard let slide = images[location.imageIndex].vmaddrSlide else { return nil }
        let descriptor = UInt(bitPattern: Int(bitPattern: UInt(location.address)) &+ slide)
        guard let key = swiftTypeIndex(ofImageAt: location.imageIndex).key(ofDescriptorAt: descriptor) else { return nil }
        let classObject = objectiveCClassIndex(ofImageAt: location.imageIndex).swiftClassObject(describedBy: descriptor)
        return SwiftTypeIdentity(key: key, descriptorLocation: location, objectiveCClassName: classObject?.name, objectiveCClassLocation: classObject?.location)
    }

    /// Where the image at `imageIndex` defines a type whose key is `key`. The
    /// type's `…Mn` symbol is looked for first, and settles it: one location.
    /// Only when no symbol names the type are the keys of the types its
    /// descriptors name alike built, and every descriptor with that key
    /// returned, in no particular order — one in the images seen so far.
    public func swiftTypeDescriptorLocations(withKey key: String, inImageAt imageIndex: Int) -> [CodeLocation] {
        let image = images[imageIndex]
        guard let slide = image.vmaddrSlide else { return [] }
        let index = swiftTypeIndex(ofImageAt: imageIndex)
        // The symbol settles it: a key spells the type the way its symbols do.
        for address in addresses(ofSymbolsNamed: "_$s" + key + "Mn", inImageAt: imageIndex) {
            let descriptor = UInt(bitPattern: Int(bitPattern: UInt(address)) &+ slide)
            if index.describesType(descriptorAt: descriptor) { return [index.location(ofRuntimeAddress: descriptor)] }
        }
        return index.descriptorLocations(withKey: key)
    }

    /// The references the image's functions make to the type: calls to its
    /// metadata accessor and the accessor's address, the address of its
    /// metadata or — for a class — of its class object, and the mangled
    /// names that name it.
    ///
    /// A mangled name names a type through a symbolic reference to the type's
    /// descriptor, which is compared directly. Only the types a name may also
    /// spell out — the standard library's and the imported ones — take
    /// demangling the names to find.
    public func references(toSwiftType identity: SwiftTypeIdentity, inImageAt imageIndex: Int) -> [CodeReference] {
        let table = existingFunctionTable(ofImageAt: imageIndex) ?? ImageFunctionTable(imageIndex: imageIndex, image: images[imageIndex])
        var scanner = ReferenceScanner(analyzer: self, table: table, matching: SwiftTypeQuery(identity: identity, analyzer: self))
        var references: [CodeReference] = []
        for index in table.starts.indices {
            scanner.scanFunction(at: index, into: &references)
        }
        return references
    }

    /// What ``references(toSwiftType:inImageAt:)`` finds, read from the
    /// image's index instead of scanned: the type's descriptor, metadata and
    /// class object are compared as the scan compares them, and the names
    /// the index keeps are taken apart only as far as the scan would.
    public func references(toSwiftType identity: SwiftTypeIdentity, in index: CodeReferenceIndex) -> [CodeReference] {
        let query = SwiftTypeQuery(identity: identity, analyzer: self)
        return index.references(toTypesMatching: { query.matches($0) }, objectiveCClassName: identity.objectiveCClassName)
    }

    /// The images among `candidates` that can reference the type: its own
    /// image; when that image exports the type, the images that can bind to
    /// it — few cache images keep a Swift symbol among their undefined ones,
    /// so the linkage is what tells (`imageIndices(linkingImageAt:among:)`);
    /// for a class, the ones its class prefilter keeps; and, for a type every
    /// image may name on its own — the standard library's and the imported
    /// ones — every Swift image.
    ///
    /// Another image reaches a type through a symbol of it — its descriptor
    /// (`…Mn`), its metadata accessor (`…Ma`), its metadata (`…N`) — so a type
    /// its image exports none of, an internal one, is referenced from that
    /// image alone. Most of a framework's types are internal, and the images
    /// linking AppKit are most of the cache.
    public func imageIndices(referencingSwiftType identity: SwiftTypeIdentity, among candidates: some Sequence<Int>) -> [Int] {
        let candidates = Array(candidates)
        let definer = identity.descriptorLocation.imageIndex
        let isExported = isSwiftTypeExported(withKey: identity.key, fromImageAt: definer)
        var result = Set<Int>()
        if candidates.contains(definer) {
            result.insert(definer)
        }
        if isExported {
            result.formUnion(imageIndices(linkingImageAt: definer, among: candidates))
        }
        if SwiftTypeQuery.mayBeSpelledOut(identity.key) {
            result.formUnion(candidates.filter { imageIndex in
                images[imageIndex].sections64.contains { $0.sectionName.hasPrefix("__swift5_") && $0.size > 0 }
            })
        }
        if let classLocation = identity.objectiveCClassLocation {
            result.formUnion(imageIndices(referencingObjectiveCClassAt: classLocation, among: candidates, includingSwiftLinkage: isExported))
        }
        return result.sorted()
    }

    /// Whether the image exports a symbol of the type with this key: what
    /// another image needs to reach it.
    func isSwiftTypeExported(withKey key: String, fromImageAt imageIndex: Int) -> Bool {
        ["Mn", "Ma", "N"].contains { exportsSymbol(named: "_$s" + key + $0, fromImageAt: imageIndex) }
    }

    /// Whether the image's export trie lists `name`, spelled as the trie
    /// spells it (`_$s…`, `_CFRelease`). Looked up in the trie: reading all of
    /// it to look up three names took SwiftUICore's first type query 0.1 s in
    /// a debug build, and keeping what was read 6 MiB.
    func exportsSymbol(named name: String, fromImageAt imageIndex: Int) -> Bool {
        images[imageIndex].exportTrie?.search(by: name) != nil
    }

    /// The types a Swift type name names, by key, in the order the name
    /// mentions them; demangles the name.
    ///
    /// The tree is demangled for this call alone — not interned in the
    /// shared `NodeCache`, not memoized for the process — since nothing
    /// bounds the names a query meets and neither cache is ever evicted.
    public func swiftTypeKeys(in name: SwiftTypeName) -> [String] {
        switch name {
        case .accessorSymbol(let symbol):
            guard let node = try? demangleAsNodeTransient(symbol) else { return [] }
            return Self.nominalKeys(in: node)
        case .mangledName(let location, _):
            guard let slide = images[location.imageIndex].vmaddrSlide,
                  let pointer = UnsafeRawPointer(bitPattern: Int(bitPattern: UInt(location.address)) &+ slide),
                  let mangledName = try? MangledName.resolve(at: pointer, in: InProcessContext.shared),
                  let node = try? SymbolicDemangler.demangleTypeUncached(for: mangledName, in: InProcessContext.shared)
            else { return [] }
            return Self.nominalKeys(in: node)
        }
    }

    // MARK: - Internals

    private static let nominalKinds: Set<Node.Kind> = [.structure, .class, .enum, .protocol, .typeAlias, .otherNominalType]
    private static let boundGenericKinds: Set<Node.Kind> = [.boundGenericStructure, .boundGenericClass, .boundGenericEnum, .boundGenericProtocol, .boundGenericOtherNominalType, .boundGenericTypeAlias]

    /// Each nominal type a type node mentions, mangled on its own as a key. A
    /// nested type names its parent only as its context: `Outer.Inner`
    /// mentions `Inner` alone. A generic argument is a type of its own,
    /// whether it binds the type or — `Regex<AnyRegexOutput>.Match` — one of
    /// its parents, which the demangled tree spells as a bound context.
    static func nominalKeys(in node: Node) -> [String] {
        var keys: [String] = []
        func walk(_ node: Node) {
            if nominalKinds.contains(node.kind) {
                var arguments: [Node] = []
                let unbound = unboundNominal(node, arguments: &arguments)
                if let key = try? mangleAsString(NodeBuilder(kind: .type, children: [unbound]).node) { keys.append(key) }
                arguments.forEach(walk)
                return
            }
            node.children.forEach(walk)
        }
        walk(node)
        return keys
    }

    /// `node` with every bound context along its parents replaced by the
    /// unbound type, and the arguments those contexts bound.
    private static func unboundNominal(_ node: Node, arguments: inout [Node]) -> Node {
        guard let context = node.children.first else { return node }
        var unboundContext: Node?
        if boundGenericKinds.contains(context.kind), let typeNode = context.children.first, let boundType = typeNode.children.first {
            if context.children.count > 1 { arguments.append(context.children[1]) }
            unboundContext = unboundNominal(boundType, arguments: &arguments)
        } else if nominalKinds.contains(context.kind) {
            let unbound = unboundNominal(context, arguments: &arguments)
            if unbound !== context { unboundContext = unbound }
        } else if context.kind == .extension, context.children.count > 1 {
            // A constrained extension's extended type, bound in
            // `Measurement<NSUnitDuration>.FormatStyle.UnitWidth`; the
            // demangled tree holds it with or without a `Type` around it.
            let isWrapped = context.children[1].kind == .type
            guard let extendedType = isWrapped ? context.children[1].children.first : context.children[1] else { return node }
            var unboundExtendedType: Node?
            if boundGenericKinds.contains(extendedType.kind), let typeNode = extendedType.children.first, let boundType = typeNode.children.first {
                if extendedType.children.count > 1 { arguments.append(extendedType.children[1]) }
                unboundExtendedType = unboundNominal(boundType, arguments: &arguments)
            } else if nominalKinds.contains(extendedType.kind) {
                let unbound = unboundNominal(extendedType, arguments: &arguments)
                if unbound !== extendedType { unboundExtendedType = unbound }
            }
            if let unboundExtendedType {
                let replacement = isWrapped ? NodeBuilder(kind: .type, children: [unboundExtendedType]).node : unboundExtendedType
                unboundContext = NodeBuilder(context).removeChild(at: 1).insertChild(replacement, at: 1).node
            }
        }
        guard let unboundContext else { return node }
        return NodeBuilder(node).removeChild(at: 0).insertChild(unboundContext, at: 0).node
    }

    /// The unslid addresses the image's symbol table and export trie give
    /// `name`.
    private func addresses(ofSymbolsNamed name: String, inImageAt imageIndex: Int) -> [UInt64] {
        let image = images[imageIndex]
        var addresses: [UInt64] = []
        name.withCString { wantedName in
            guard let symbols = image.symbols64 else { return }
            for symbolIndex in 0 ..< symbols.numberOfSymbols {
                let entry = symbols.symbols[symbolIndex]
                guard entry.n_type & 0xE0 == 0, entry.n_type & 0x0E == 0x0E,
                      strcmp(symbols.stringBase.advanced(by: Int(entry.n_un.n_strx)), wantedName) == 0
                else { continue }
                addresses.append(entry.n_value)
            }
        }
        if let headerAddress = image.segments64.first(where: { $0.segmentName == "__TEXT" }).map({ UInt64($0.layout.vmaddr) }),
           let offset = image.exportTrie?.search(by: name)?.offset {
            addresses.append(UInt64(bitPattern: Int64(bitPattern: headerAddress) &+ Int64(offset)))
        }
        return addresses
    }
}

/// What a type query keeps: the references to one Swift type, however the
/// code reaches it. One query serves one scan.
final class SwiftTypeQuery {
    private let identity: SwiftTypeIdentity
    private let analyzer: CrossReferenceAnalyzer
    /// A type imported from C or Objective-C: every image that uses it holds
    /// a descriptor of its own, so a descriptor is the type's when its key
    /// is.
    private let isImported: Bool
    private let mayBeSpelledOut: Bool
    /// The name the type's descriptor gives it — compared before any other
    /// descriptor's key is built.
    private let typeName: String?
    private var descriptorMatches: [CodeLocation: Bool] = [:]
    private var nameMatches: [SwiftTypeName: Bool] = [:]

    init(identity: SwiftTypeIdentity, analyzer: CrossReferenceAnalyzer) {
        self.identity = identity
        self.analyzer = analyzer
        self.isImported = identity.key.hasPrefix("So") || identity.key.hasPrefix("SC")
        self.mayBeSpelledOut = Self.mayBeSpelledOut(identity.key)
        var typeName: String?
        if let slide = analyzer.images[identity.descriptorLocation.imageIndex].vmaddrSlide,
           let name = SwiftTypeIndex.name(ofDescriptorAt: UInt(bitPattern: Int(bitPattern: UInt(identity.descriptorLocation.address)) &+ slide)) {
            typeName = String(cString: name)
        }
        self.typeName = typeName
    }

    /// Whether mangled names may spell the type out rather than refer to its
    /// descriptor: a type of the standard library (`Sa`, `s6UInt16V`), of
    /// `_Concurrency` (`ScT`) or imported (`So6CGRectV`). Any other key starts
    /// with its module's name, `7SwiftUI…`, and names refer to such a type
    /// through a symbolic reference.
    static func mayBeSpelledOut(_ key: String) -> Bool {
        guard let first = key.utf8.first else { return false }
        return first == UInt8(ascii: "s") || first == UInt8(ascii: "S")
    }

    func matches(_ target: CodeReferenceTarget) -> Bool {
        switch target {
        case .swiftType(let descriptor):
            return matchesDescriptor(at: descriptor)
        case .swiftTypeName(let name):
            if let known = nameMatches[name] { return known }
            let result = matches(name)
            nameMatches[name] = result
            return result
        case .objectiveCClass(_, let location):
            return location == identity.objectiveCClassLocation
        default:
            return false
        }
    }

    private func matchesDescriptor(at location: CodeLocation) -> Bool {
        if location == identity.descriptorLocation { return true }
        guard isImported, let typeName else { return false }
        if let known = descriptorMatches[location] { return known }
        var result = false
        if let slide = analyzer.images[location.imageIndex].vmaddrSlide {
            let descriptor = UInt(bitPattern: Int(bitPattern: UInt(location.address)) &+ slide)
            if let name = SwiftTypeIndex.name(ofDescriptorAt: descriptor), strcmp(name, typeName) == 0 {
                result = analyzer.swiftTypeIndex(ofImageAt: location.imageIndex).key(ofDescriptorAt: descriptor) == identity.key
            }
        }
        descriptorMatches[location] = result
        return result
    }

    private func matches(_ name: SwiftTypeName) -> Bool {
        switch name {
        case .accessorSymbol:
            // A symbol spells every type out.
            return analyzer.swiftTypeKeys(in: name).contains(identity.key)
        case .mangledName(let location, let length):
            guard let slide = analyzer.images[location.imageIndex].vmaddrSlide,
                  let bytes = UnsafePointer<UInt8>(bitPattern: Int(bitPattern: UInt(location.address)) &+ slide)
            else { return false }
            var index = 0
            while index < length {
                let byte = bytes[index]
                if byte == 0x01 || byte == 0x02, index + 5 <= length {
                    // A symbolic reference to a context descriptor, direct or
                    // through a pointer.
                    let field = UInt(bitPattern: bytes + index + 1)
                    let relative = UnsafeRawPointer(bytes + index + 1).loadUnaligned(as: Int32.self)
                    var descriptor = UInt(bitPattern: Int(bitPattern: field) &+ Int(relative))
                    if byte == 0x02 {
                        guard analyzer.isMapped(runtimeAddress: descriptor, length: 8), let slot = UnsafeRawPointer(bitPattern: descriptor) else {
                            index += 5
                            continue
                        }
                        descriptor = StoredPointer.address(in: slot.loadUnaligned(as: UInt64.self))
                    }
                    if let descriptorLocation = analyzer.location(ofDescriptorAtRuntimeAddress: descriptor), matchesDescriptor(at: descriptorLocation) {
                        return true
                    }
                    index += 5
                } else if byte >= 0x01, byte <= 0x17 {
                    index += 5
                } else if byte >= 0x18, byte <= 0x1F {
                    index += 9
                } else {
                    index += 1
                }
            }
            guard mayBeSpelledOut else { return false }
            return analyzer.swiftTypeKeys(in: name).contains(identity.key)
        }
    }
}

extension CrossReferenceAnalyzer {
    /// Where the context descriptor at the runtime `address` lies, when it
    /// lies in an image.
    func location(ofDescriptorAtRuntimeAddress address: UInt) -> CodeLocation? {
        guard let imageIndex = imageIndex(containingRuntimeAddress: address), let slide = images[imageIndex].vmaddrSlide else { return nil }
        return CodeLocation(imageIndex: imageIndex, address: UInt64(bitPattern: Int64(bitPattern: UInt64(address)) &- Int64(slide)))
    }
}
