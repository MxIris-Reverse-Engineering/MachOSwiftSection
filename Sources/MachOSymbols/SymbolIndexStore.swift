import Foundation
import FoundationToolbox
import MachOKit
import MachOExtensions
import Demangling
import OrderedCollections
import Utilities
import Dependencies
import MemberwiseInit
@_spi(Internals) import MachOCaches
import AsyncAlgorithms

@_spi(ForSymbolViewer)
@_spi(Internals)
@Loggable(.private)
public final class SymbolIndexStore: SharedCache<SymbolIndexStore.Storage>, @unchecked Sendable {
    public enum MemberKind: Hashable, CaseIterable, CustomStringConvertible, Sendable {
        fileprivate struct Traits: OptionSet, Hashable, Sendable {
            fileprivate let rawValue: Int
            fileprivate init(rawValue: Int) {
                self.rawValue = rawValue
            }

            fileprivate static let isStatic = Traits(rawValue: 1 << 0)
            fileprivate static let isStorage = Traits(rawValue: 1 << 1)
            fileprivate static let inExtension = Traits(rawValue: 1 << 2)
        }

        case allocator(inExtension: Bool)
        case deallocator
        case constructor(inExtension: Bool)
        case destructor
        case `subscript`(inExtension: Bool, isStatic: Bool)
        case variable(inExtension: Bool, isStatic: Bool, isStorage: Bool)
        case function(inExtension: Bool, isStatic: Bool)

        public static let allCases: [SymbolIndexStore.MemberKind] = [
            .allocator(inExtension: false),
            .allocator(inExtension: true),
            .deallocator,
            .constructor(inExtension: false),
            .constructor(inExtension: true),
            .destructor,
            .subscript(inExtension: false, isStatic: false),
            .subscript(inExtension: false, isStatic: true),
            .subscript(inExtension: true, isStatic: false),
            .subscript(inExtension: true, isStatic: true),
            .variable(inExtension: false, isStatic: false, isStorage: false),
            .variable(inExtension: true, isStatic: true, isStorage: true),
            .variable(inExtension: true, isStatic: false, isStorage: false),
            .variable(inExtension: false, isStatic: true, isStorage: false),
            .variable(inExtension: false, isStatic: false, isStorage: true),
            .variable(inExtension: true, isStatic: true, isStorage: false),
            .variable(inExtension: false, isStatic: true, isStorage: true),
            .variable(inExtension: true, isStatic: false, isStorage: true),
            .function(inExtension: false, isStatic: false),
            .function(inExtension: false, isStatic: true),
            .function(inExtension: true, isStatic: false),
            .function(inExtension: true, isStatic: true),
        ]

        public var description: String {
            switch self {
            case .allocator(inExtension: let inExtension):
                return "Allocator" + (inExtension ? " (In Extension)" : "")
            case .deallocator:
                return "Deallocator"
            case .constructor(inExtension: let inExtension):
                return "Constructor" + (inExtension ? " (In Extension)" : "")
            case .destructor:
                return "Destructor"
            case .subscript(inExtension: let inExtension, isStatic: let isStatic):
                return (isStatic ? "Static " : "") + "Subscript" + (inExtension ? " (In Extension)" : "")
            case .variable(inExtension: let inExtension, isStatic: let isStatic, isStorage: let isStorage):
                return (isStatic ? "Static " : "") + (isStorage ? "Stored " : "") + "Variable" + (inExtension ? " (In Extension)" : "")
            case .function(inExtension: let inExtension, isStatic: let isStatic):
                return (isStatic ? "Static " : "") + "Function" + (inExtension ? " (In Extension)" : "")
            }
        }
    }

    public enum GlobalKind: Hashable, CaseIterable, CustomStringConvertible, Sendable {
        case variable(isStorage: Bool)
        case function

        public static let allCases: [SymbolIndexStore.GlobalKind] = [
            .variable(isStorage: false),
            .variable(isStorage: true),
            .function,
        ]

        public var description: String {
            switch self {
            case .variable(isStorage: let isStorage):
                return (isStorage ? "Stored " : "") + "Global Variable"
            case .function:
                return "Global Function"
            }
        }
    }

    public struct TypeInfo: Sendable {
        public enum Kind: Sendable {
            case `enum`
            case `struct`
            case `class`
            case `protocol`
            case typeAlias
        }

        public let name: String
        public let kind: Kind
    }

    /// Pre-extracted information about a thunk symbol that carries an attribute
    /// annotation (for example `@objc` / `@nonobjc`), bucketed by the printed
    /// name of the type the thunked member belongs to. Consumers use this to
    /// map attribute annotations back onto already-built member definitions
    /// without re-parsing the thunk's demangled node tree per type.
    public struct ThunkAttributeMember: Sendable {
        public let memberName: String
        public let isStatic: Bool
        public let isInit: Bool

        public init(memberName: String, isStatic: Bool, isInit: Bool) {
            self.memberName = memberName
            self.isStatic = isStatic
            self.isInit = isInit
        }
    }

    typealias IndexedSymbol = DemangledSymbol
    typealias AllSymbols = [IndexedSymbol]
    typealias GlobalSymbols = [IndexedSymbol]
    typealias MemberSymbols = OrderedDictionary<String, OrderedDictionary<Node, [IndexedSymbol]>>
    typealias OpaqueTypeDescriptorSymbol = IndexedSymbol

    public final class Storage: @unchecked Sendable {
        private(set) var typeInfoByName: [String: TypeInfo] = [:]

        private(set) var globalSymbolsByKind: OrderedDictionary<GlobalKind, GlobalSymbols> = [:]

        private(set) var opaqueTypeDescriptorSymbolByNode: OrderedDictionary<Node, OpaqueTypeDescriptorSymbol> = [:]

        private(set) var memberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]

        private(set) var methodDescriptorMemberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]

        private(set) var protocolWitnessMemberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]

        private(set) var symbolsByKind: OrderedDictionary<Node.Kind, AllSymbols> = [:]

        private(set) var symbolsByOffset: OrderedDictionary<Int, [Symbol]> = [:]

        private(set) var demangledNodeBySymbol: [Symbol: Node] = [:]

        private(set) var thunkAttributeMembersByKindAndTypeName: [Node.Kind: [String: [ThunkAttributeMember]]] = [:]

        fileprivate func appendSymbol(_ symbol: IndexedSymbol, for kind: Node.Kind) {
            symbolsByKind[kind, default: []].append(symbol)
        }

        fileprivate func setOpaqueTypeDescriptorSymbol(_ symbol: OpaqueTypeDescriptorSymbol, for node: Node) {
            opaqueTypeDescriptorSymbolByNode[node] = symbol
        }

        fileprivate func setDemangledNode(_ demangledNode: Node?, for symbol: Symbol) {
            demangledNodeBySymbol[symbol] = demangledNode
        }

        fileprivate func setSymbolsByOffset(_ symbolsByOffset: OrderedDictionary<Int, [Symbol]>) {
            self.symbolsByOffset = symbolsByOffset
        }

        fileprivate func setDemangledNodeBySymbol(_ demangledNodeBySymbol: [Symbol: Node]) {
            self.demangledNodeBySymbol = demangledNodeBySymbol
        }

        fileprivate func setMemberSymbols(for result: ProcessMemberSymbolResult) {
            memberSymbolsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNode, default: []].append(result.indexedSymbol)
            typeInfoByName[result.typeName] = result.typeInfo
        }

        fileprivate func setMethodDescriptorMemberSymbols(for result: ProcessMemberSymbolResult) {
            methodDescriptorMemberSymbolsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNode, default: []].append(result.indexedSymbol)
            typeInfoByName[result.typeName] = result.typeInfo
        }

        fileprivate func setProtocolWitnessMemberSymbols(for result: ProcessMemberSymbolResult) {
            protocolWitnessMemberSymbolsByKind[result.memberKind, default: [:]][result.typeName, default: [:]][result.typeNode, default: []].append(result.indexedSymbol)
            typeInfoByName[result.typeName] = result.typeInfo
        }

        fileprivate func setGlobalSymbols(for result: ProcessGlobalSymbolResult) {
            globalSymbolsByKind[result.kind, default: []].append(result.indexedSymbol)
        }

        fileprivate func appendThunkAttributeMember(_ member: ThunkAttributeMember, forKind thunkKind: Node.Kind, typeName: String) {
            thunkAttributeMembersByKindAndTypeName[thunkKind, default: [:]][typeName, default: []].append(member)
        }
    }

    public static let shared = SymbolIndexStore()

    private override init() {
        super.init()
    }

    public override func buildStorage<MachO: MachORepresentableWithCache>(for machO: MachO) -> Storage? {
        return buildStorageImpl(for: machO, progressContinuation: nil)
    }

    private func buildStorageImpl<MachO: MachORepresentableWithCache>(
        for machO: MachO,
        progressContinuation: AsyncStream<Progress>.Continuation?
    ) -> Storage? {
        let storage = Storage()
        var cachedSymbols: Set<String> = []
        var symbolByName: OrderedDictionary<String, Symbol> = [:]
        var symbolsByOffset: OrderedDictionary<Int, [Symbol]> = [:]

        for symbol in machO.symbols where symbol.name.isSwiftSymbol && !symbol.nlist.isExternal {
            var offset = symbol.offset
            symbolsByOffset[offset, default: []].append(.init(offset: offset, name: symbol.name, nlist: symbol.nlist))
            if let cache = machO.cache, offset >= 0, machO is MachOFile {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
                symbolsByOffset[offset, default: []].append(.init(offset: offset, name: symbol.name, nlist: symbol.nlist))
            }
            symbolByName[symbol.name] = .init(offset: offset, name: symbol.name, nlist: symbol.nlist)
            cachedSymbols.insert(symbol.name)
        }

        for exportedSymbol in machO.exportedSymbols where exportedSymbol.name.isSwiftSymbol {
            if var offset = exportedSymbol.offset, symbolByName[exportedSymbol.name] == nil {
                symbolsByOffset[offset, default: []].append(.init(offset: offset, name: exportedSymbol.name))
                if machO is MachOFile {
                    offset += machO.startOffset
                }
                symbolsByOffset[offset, default: []].append(.init(offset: offset, name: exportedSymbol.name))
                symbolByName[exportedSymbol.name] = .init(offset: offset, name: exportedSymbol.name)
            }
        }

        // Phase 1: Parallel demangling
        let symbolArray = Array(symbolByName.values)
        let totalSymbolCount = symbolArray.count

        let demangledNodes = symbolArray.concurrentMap { try? demangleAsNode($0.name) }

        // Phase 2: Sequential indexing
        var demangledNodeBySymbol: [Symbol: Node] = [:]
        demangledNodeBySymbol.reserveCapacity(totalSymbolCount)

        for symbolIndex in 0..<totalSymbolCount {
            if symbolIndex % 500 == 0 {
                progressContinuation?.yield(Progress(currentCount: symbolIndex, totalCount: totalSymbolCount))
            }

            let symbol = symbolArray[symbolIndex]
            guard let rootNode = demangledNodes[symbolIndex] else { continue }

            demangledNodeBySymbol[symbol] = rootNode

            guard rootNode.isKind(of: .global), let node = rootNode.children.first else { continue }

            storage.appendSymbol(DemangledSymbol(symbol: symbol, demangledNode: rootNode), for: node.kind)

            if node.kind == .objCAttribute || node.kind == .nonObjCAttribute {
                if let extracted = processThunkAttributeSymbol(thunkKind: node.kind, rootNode: rootNode) {
                    storage.appendThunkAttributeMember(extracted.member, forKind: node.kind, typeName: extracted.typeName)
                }
                continue
            }

            if rootNode.isGlobal {
                if !symbol.isExternal {
                    if let result = processGlobalSymbol(symbol, node: node, rootNode: rootNode) {
                        storage.setGlobalSymbols(for: result)
                    }
                }
            } else {
                if node.kind == .methodDescriptor, let firstChild = node.children.first {
                    if let result = processMemberSymbol(symbol, node: firstChild, rootNode: rootNode) {
                        storage.setMethodDescriptorMemberSymbols(for: result)
                    }
                } else if node.kind == .protocolWitness, let firstChild = node.children.first {
                    if let result = processMemberSymbol(symbol, node: firstChild, rootNode: rootNode) {
                        storage.setProtocolWitnessMemberSymbols(for: result)
                    }
                } else if node.kind == .mergedFunction, let secondChild = rootNode.children.second {
                    if let result = processMemberSymbol(symbol, node: secondChild, rootNode: rootNode) {
                        storage.setMemberSymbols(for: result)
                    }
                } else if node.kind == .opaqueTypeDescriptor, let firstChild = node.children.first, firstChild.kind == .opaqueReturnTypeOf, let memberSymbol = firstChild.children.first {
                    if symbol.offset > 0 {
                        storage.setOpaqueTypeDescriptorSymbol(DemangledSymbol(symbol: symbol, demangledNode: rootNode), for: memberSymbol)
                    }
                } else {
                    if let result = processMemberSymbol(symbol, node: node, rootNode: rootNode) {
                        storage.setMemberSymbols(for: result)
                    }
                }
            }
        }
        progressContinuation?.yield(Progress(currentCount: totalSymbolCount, totalCount: totalSymbolCount))

        storage.setSymbolsByOffset(symbolsByOffset)

        storage.setDemangledNodeBySymbol(demangledNodeBySymbol)

        return storage
    }

    fileprivate struct ProcessMemberSymbolResult: Sendable {
        let memberKind: MemberKind
        let typeName: String
        let typeNode: Node
        let typeInfo: TypeInfo
        let indexedSymbol: IndexedSymbol
    }

    private func processMemberSymbol(_ symbol: Symbol, node: Node, rootNode: Node) -> ProcessMemberSymbolResult? {
        if node.kind == .static, let firstChild = node.children.first, firstChild.kind.isMember {
            return processMemberSymbol(symbol, node: firstChild, rootNode: rootNode, traits: [.isStatic])
        } else if node.kind.isMember {
            return processMemberSymbol(symbol, node: node, rootNode: rootNode, traits: [])
        }
        return nil
    }

    private func processMemberSymbol(_ symbol: Symbol, node: Node, rootNode: Node, traits: MemberKind.Traits) -> ProcessMemberSymbolResult? {
        var traits = traits
        let node = node
        switch node.kind {
        case .allocator:
            guard var first = node.children.first else { return nil }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            return processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .allocator(inExtension: traits.contains(.inExtension)))
        case .deallocator:
            guard let first = node.children.first else { return nil }
            return processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .deallocator)
        case .constructor:
            guard var first = node.children.first else { return nil }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            return processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .constructor(inExtension: traits.contains(.inExtension)))
        case .destructor:
            guard let first = node.children.first else { return nil }
            return processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .destructor)
        case .function:
            guard var first = node.children.first else { return nil }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            return processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .function(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic)))
        case .variable:
            // Stored variable reached directly (not through getter/setter)
            traits.insert(.isStorage)
            var first = node.children.first
            if first?.kind == .extension, let type = first?.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            if let first {
                return processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .variable(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic), isStorage: traits.contains(.isStorage)))
            }
        case .getter,
             .setter:
            if let variableNode = node.children.first, variableNode.kind == .variable, var first = variableNode.children.first {
                if first.kind == .extension, let type = first.children.at(1) {
                    traits.insert(.inExtension)
                    first = type
                }
                return processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .variable(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic), isStorage: traits.contains(.isStorage)))
            } else if let subscriptNode = node.children.first, subscriptNode.kind == .subscript, var first = subscriptNode.children.first {
                if first.kind == .extension, let type = first.children.at(1) {
                    traits.insert(.inExtension)
                    first = type
                }
                return processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .subscript(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic)))
            }
        default:
            break
        }
        return nil
    }

    private func processMemberSymbol(_ symbol: Symbol, node: Node, rootNode: Node, memberKind: MemberKind) -> ProcessMemberSymbolResult? {
        let typeNode = Node.create(kind: .type, child: node)
        let typeName = typeNode.print(using: .interfaceTypeBuilderOnly)
        if let typeKind = node.kind.typeKind {
//            typeInfoByName[typeName] = .init(name: typeName, kind: typeKind)
//            storage[memberKind, default: [:]][typeName, default: [:]][typeNode, default: []].append(IndexedSymbol(DemangledSymbol(symbol: symbol, demangledNode: rootNode)))
            return .init(memberKind: memberKind, typeName: typeName, typeNode: typeNode, typeInfo: .init(name: typeName, kind: typeKind), indexedSymbol: DemangledSymbol(symbol: symbol, demangledNode: rootNode))
        }
        return nil
    }

    /// Extracts `(typeName, ThunkAttributeMember)` from a thunk symbol whose root
    /// demangled node has an attribute marker child (`.objCAttribute` /
    /// `.nonObjCAttribute`). Returns `nil` if the thunk does not wrap a named
    /// member whose parent context can be resolved to a Swift type name.
    private func processThunkAttributeSymbol(
        thunkKind: Node.Kind,
        rootNode: Node
    ) -> (typeName: String, member: ThunkAttributeMember)? {
        guard let memberNode = rootNode.children.first(where: { $0.kind != thunkKind }) else { return nil }

        let isStatic: Bool
        let unwrappedMemberNode: Node
        if memberNode.kind == .static, let innerChild = memberNode.children.first {
            isStatic = true
            unwrappedMemberNode = innerChild
        } else {
            isStatic = false
            unwrappedMemberNode = memberNode
        }

        let extractedMemberName: String?
        let contextNode: Node?

        switch unwrappedMemberNode.kind {
        case .function, .constructor, .allocator, .variable:
            contextNode = unwrappedMemberNode.children.first.map(Self.unwrapExtensionContext)
            extractedMemberName = unwrappedMemberNode.identifier
        case .getter, .setter:
            if let innerVariable = unwrappedMemberNode.children.first, innerVariable.kind == .variable {
                contextNode = innerVariable.children.first.map(Self.unwrapExtensionContext)
                extractedMemberName = innerVariable.identifier
            } else {
                return nil
            }
        default:
            return nil
        }

        guard let contextNode, let extractedMemberName else { return nil }

        let typeName = Node.create(kind: .type, child: contextNode).print(using: .interfaceTypeBuilderOnly)

        let isInit = unwrappedMemberNode.kind == .allocator || unwrappedMemberNode.kind == .constructor

        return (
            typeName: typeName,
            member: ThunkAttributeMember(memberName: extractedMemberName, isStatic: isStatic, isInit: isInit)
        )
    }

    /// If the given node is an `.extension` wrapper, return the extended type node
    /// (the second child, per Swift demangler's extension node layout:
    /// `extension(module, extendedType, ?genericSignature)`). Otherwise, return
    /// the node as-is.
    private static func unwrapExtensionContext(_ node: Node) -> Node {
        if node.kind == .extension, let extendedType = node.children.at(1) {
            return extendedType
        }
        return node
    }

    fileprivate struct ProcessGlobalSymbolResult: Sendable {
        let kind: GlobalKind
        let indexedSymbol: IndexedSymbol
    }

    private func processGlobalSymbol(_ symbol: Symbol, node: Node, rootNode: Node) -> ProcessGlobalSymbolResult? {
        switch node.kind {
        case .function:
            return .init(kind: .function, indexedSymbol: DemangledSymbol(symbol: symbol, demangledNode: rootNode))
        case .variable:
            // When we reach .variable directly (not through getter/setter),
            // this is a stored variable declaration
            return .init(kind: .variable(isStorage: true), indexedSymbol: DemangledSymbol(symbol: symbol, demangledNode: rootNode))
        case .getter,
             .setter:
            if let variableNode = node.children.first, variableNode.kind == .variable {
                return processGlobalSymbol(symbol, node: variableNode, rootNode: rootNode)
            }
        default:
            break
        }
        return nil
    }

    public func allSymbols<MachO: MachORepresentableWithCache>(in machO: MachO) -> [DemangledSymbol] {
        if let symbols = storage(in: machO)?.symbolsByKind.values.flatMap({ $0 }) {
            return symbols
        } else {
            return []
        }
    }

    public func symbolsByKind<MachO: MachORepresentableWithCache>(in machO: MachO) -> OrderedDictionary<Node.Kind, [DemangledSymbol]> {
        if let symbols = storage(in: machO)?.symbolsByKind {
            return symbols.mapValues { $0 }
        } else {
            return [:]
        }
    }

    public func typeInfo<MachO: MachORepresentableWithCache>(for name: String, in machO: MachO) -> TypeInfo? {
        return storage(in: machO)?.typeInfoByName[name]
    }

    public func symbols<MachO: MachORepresentableWithCache>(of kinds: Node.Kind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.symbolsByKind[$0] ?? [] }.reduce(into: []) { $0 += $1 }
    }

    /// Returns the pre-extracted thunk-attribute members whose parent type
    /// name matches `typeName`. `thunkKind` is the demangler attribute marker
    /// kind (e.g. `.objCAttribute`, `.nonObjCAttribute`). Lookup is O(1) in the
    /// typeName bucket; no per-type scan of all thunk symbols is needed.
    public func thunkAttributeMembers<MachO: MachORepresentableWithCache>(
        of thunkKind: Node.Kind,
        for typeName: String,
        in machO: MachO
    ) -> [ThunkAttributeMember] {
        return storage(in: machO)?.thunkAttributeMembersByKindAndTypeName[thunkKind]?[typeName] ?? []
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.memberSymbolsByKind[$0]?.values.flatMap { $0.values.flatMap { $0 } } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.memberSymbolsByKind[$0]?[name]?.values.flatMap { $0 } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, node: Node, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.memberSymbolsByKind[$0]?[name]?[node] ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., excluding names: borrowing Set<String>, in machO: MachO) -> OrderedDictionary<Node, OrderedDictionary<MemberKind, [DemangledSymbol]>> {
        let filtered: OrderedDictionary<MemberKind, MemberSymbols> = kinds.reduce(into: [:]) { $0[$1] = storage(in: machO)?.memberSymbolsByKind[$1]?.filter { !names.contains($0.key) } ?? [:] }

        var result: OrderedDictionary<Node, OrderedDictionary<MemberKind, [DemangledSymbol]>> = [:]
        for (kind, memberSymbols) in filtered {
            for (_, symbols) in memberSymbols {
                for (node, symbols) in symbols {
                    result[node, default: [:]][kind, default: []].append(contentsOf: symbols)
                }
            }
        }
        return result
    }

    public func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.methodDescriptorMemberSymbolsByKind[$0]?.values.flatMap { $0.values.flatMap { $0 } } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.methodDescriptorMemberSymbolsByKind[$0]?[name]?.values.flatMap { $0 } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.protocolWitnessMemberSymbolsByKind[$0]?.values.flatMap { $0.values.flatMap { $0 } } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.protocolWitnessMemberSymbolsByKind[$0]?[name]?.values.flatMap { $0 } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func globalSymbols<MachO: MachORepresentableWithCache>(of kinds: GlobalKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { storage(in: machO)?.globalSymbolsByKind[$0] ?? [] }.reduce(into: []) { $0 += $1 }
    }

    public func allOpaqueTypeDescriptorSymbols<MachO: MachORepresentableWithCache>(in machO: MachO) -> OrderedDictionary<Node, DemangledSymbol>? {
        return storage(in: machO)?.opaqueTypeDescriptorSymbolByNode.mapValues {
            return $0
        }
    }

    public func opaqueTypeDescriptorSymbol<MachO: MachORepresentableWithCache>(for node: Node, in machO: MachO) -> DemangledSymbol? {
        return storage(in: machO)?.opaqueTypeDescriptorSymbolByNode[node].map {
            return $0
        }
    }

    package func symbols<MachO: MachORepresentableWithCache>(for offset: Int, in machO: MachO) -> Symbols? {
        if let symbols = storage(in: machO)?.symbolsByOffset[offset], !symbols.isEmpty {
            return .init(offset: offset, symbols: symbols)
        } else {
            return nil
        }
    }

    package func demangledNode<MachO: MachORepresentableWithCache>(for symbol: Symbol, in machO: MachO) -> Node? {
        guard let cacheStorage = storage(in: machO) else { return nil }
        if let node = cacheStorage.demangledNodeBySymbol[symbol] {
            return node
        } else if let node = try? demangleAsNode(symbol.name) {
            cacheStorage.setDemangledNode(node, for: symbol)
            return node
        } else {
            return nil
        }
    }

    public struct Progress: Sendable {
        public let currentCount: Int
        public let totalCount: Int
    }

    public func prepare<MachO: MachORepresentableWithCache>(in machO: MachO) {
        _ = storage(in: machO)
    }

    public func prepareWithProgress<MachO: MachORepresentableWithCache>(in machO: MachO) -> AsyncStream<Progress> {
        let (stream, continuation) = AsyncStream<Progress>.makeStream()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { continuation.finish() }
            guard let self else { return }
            // continuation flows into buildStorageImpl via closure capture only.
            // No shared instance state is involved, so concurrent calls cannot
            // interfere with each other's progress streams.
            _ = self.storage(in: machO) { machO in
                self.buildStorageImpl(for: machO, progressContinuation: continuation)
            }
        }
        return stream
    }
}

extension Node.Kind {
    fileprivate var isMember: Bool {
        switch self {
        case .allocator,
             .deallocator,
             .constructor,
             .destructor,
             .function,
             .getter,
             .setter,
             .methodDescriptor,
             .protocolWitness,
             .variable:
            return true
        default:
            return false
        }
    }

    fileprivate var typeKind: SymbolIndexStore.TypeInfo.Kind? {
        switch self {
        case .enum:
            return .enum
        case .structure:
            return .struct
        case .class:
            return .class
        case .protocol:
            return .protocol
        case .typeAlias:
            return .typeAlias
        default:
            return nil
        }
    }
}

private enum SymbolIndexStoreKey: DependencyKey {
    static let liveValue: SymbolIndexStore = .shared
    static let testValue: SymbolIndexStore = .shared
}

@_spi(ForSymbolViewer)
@_spi(Internals)
extension DependencyValues {
    public var symbolIndexStore: SymbolIndexStore {
        get { self[SymbolIndexStoreKey.self] }
        set { self[SymbolIndexStoreKey.self] = newValue }
    }
}

extension Node {
    package var isGlobal: Bool {
        guard let first = children.first else { return false }
        guard first.isKind(of: .getter, .setter, .function, .variable) else { return false }
        if first.isKind(of: .getter, .setter), let variable = first.children.first, variable.isKind(of: .variable) {
            return variable.children.first?.isKind(of: .module) ?? false
        } else {
            return first.children.first?.isKind(of: .module) ?? false
        }
    }

    package var isAccessor: Bool {
        return isKind(of: .getter, .setter, .modifyAccessor, .readAccessor)
    }

    package var hasAccessor: Bool {
        return contains { $0.isAccessor }
    }
}

extension Symbol {
    package var isExternal: Bool {
        nlist?.isExternal ?? false
    }
}

extension NlistProtocol {
    package var isExternal: Bool {
        guard let flags = flags, let type = flags.type else { return false }
        return flags.contains(.ext) && type == .undf
    }
}
