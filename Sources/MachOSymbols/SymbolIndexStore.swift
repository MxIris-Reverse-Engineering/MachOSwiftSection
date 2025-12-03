import Foundation
import MachOKit
import MachOExtensions
import Demangling
import OrderedCollections
import Utilities
import Dependencies
import MemberwiseInit
@_spi(Internals) import MachOCaches
import AsyncAlgorithms
import SwiftStdlibToolbox

@_spi(ForSymbolViewer)
@_spi(Internals)
public final class SymbolIndexStore: SharedCache<SymbolIndexStore.Entry>, @unchecked Sendable {
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

    fileprivate final class ConsumableValue<Value: Sendable>: Sendable {
        let wrappedValue: Value
        @Mutex
        var isConsumed: Bool = false

        init(_ wrappedValue: Value) {
            self.wrappedValue = wrappedValue
            self.isConsumed = false
        }
    }

    fileprivate typealias IndexedSymbol = ConsumableValue<DemangledSymbol>

    fileprivate typealias AllSymbols = [IndexedSymbol]
    fileprivate typealias GlobalSymbols = [IndexedSymbol]
    fileprivate typealias MemberSymbols = OrderedDictionary<String, OrderedDictionary<Node, [IndexedSymbol]>>
    fileprivate typealias OpaqueTypeDescriptorSymbol = IndexedSymbol

    public final class Entry: Sendable {
        @Mutex
        fileprivate private(set) var typeInfoByName: [String: TypeInfo] = [:]
        @Mutex
        fileprivate private(set) var globalSymbolsByKind: OrderedDictionary<GlobalKind, GlobalSymbols> = [:]
        @Mutex
        fileprivate private(set) var opaqueTypeDescriptorSymbolByNode: OrderedDictionary<Node, OpaqueTypeDescriptorSymbol> = [:]
        @Mutex
        fileprivate private(set) var memberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]
        @Mutex
        fileprivate private(set) var methodDescriptorMemberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]
        @Mutex
        fileprivate private(set) var protocolWitnessMemberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]
        @Mutex
        fileprivate private(set) var symbolsByKind: OrderedDictionary<Node.Kind, AllSymbols> = [:]
        @Mutex
        fileprivate private(set) var symbolsByOffset: OrderedDictionary<Int, [Symbol]> = [:]
        @Mutex
        fileprivate private(set) var demangledNodeBySymbol: [Symbol: Node] = [:]

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
    }

    public static let shared = SymbolIndexStore()

    private override init() { super.init() }

    public override func buildEntry<MachO>(for machO: MachO) -> Entry? where MachO: MachORepresentableWithCache {
        let entry = Entry()
        var cachedSymbols: Set<String> = []
        var symbolsByOffset: OrderedDictionary<Int, [Symbol]> = [:]
        var symbolByName: OrderedDictionary<String, Symbol> = [:]
        var demangledNodeBySymbol: [Symbol: Node] = [:]

        for symbol in machO.symbols where symbol.name.isSwiftSymbol {
            var offset = symbol.offset
            symbolsByOffset[offset, default: []].append(.init(offset: offset, name: symbol.name, nlist: symbol.nlist))
            if let cache = machO.cache, offset != 0, machO is MachOFile {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
                symbolsByOffset[offset, default: []].append(.init(offset: offset, name: symbol.name, nlist: symbol.nlist))
            }
            cachedSymbols.insert(symbol.name)
        }

        for exportedSymbol in machO.exportedSymbols where exportedSymbol.name.isSwiftSymbol {
            if var offset = exportedSymbol.offset, symbolByName[exportedSymbol.name] == nil {
                symbolsByOffset[offset, default: []].append(.init(offset: offset, name: exportedSymbol.name))
                offset += machO.startOffset
                symbolsByOffset[offset, default: []].append(.init(offset: offset, name: exportedSymbol.name))
                symbolByName[exportedSymbol.name] = .init(offset: offset, name: exportedSymbol.name)
            }
        }

        for symbol in symbolByName.values {
            do {
                let rootNode = try demangleAsNode(symbol.name)

                demangledNodeBySymbol[symbol] = rootNode

                guard rootNode.isKind(of: .global), let node = rootNode.children.first else { continue }

                entry.appendSymbol(IndexedSymbol(DemangledSymbol(symbol: symbol, demangledNode: rootNode)), for: node.kind)
                if rootNode.isGlobal {
                    if !symbol.isExternal {
                        if let result = processGlobalSymbol(symbol, node: node, rootNode: rootNode) {
                            entry.setGlobalSymbols(for: result)
                        }
                    }
                } else {
                    if node.kind == .methodDescriptor, let firstChild = node.children.first {
                        if let result = processMemberSymbol(symbol, node: firstChild, rootNode: rootNode) {
                            entry.setMethodDescriptorMemberSymbols(for: result)
                        }
                    } else if node.kind == .protocolWitness, let firstChild = node.children.first {
                        if let result = processMemberSymbol(symbol, node: firstChild, rootNode: rootNode) {
                            entry.setProtocolWitnessMemberSymbols(for: result)
                        }
                    } else if node.kind == .mergedFunction, let secondChild = rootNode.children.second {
                        if let result = processMemberSymbol(symbol, node: secondChild, rootNode: rootNode) {
                            entry.setMemberSymbols(for: result)
                        }
                    } else if node.kind == .opaqueTypeDescriptor, let firstChild = node.children.first, firstChild.kind == .opaqueReturnTypeOf, let memberSymbol = firstChild.children.first {
                        if symbol.offset > 0 {
                            entry.setOpaqueTypeDescriptorSymbol(IndexedSymbol(DemangledSymbol(symbol: symbol, demangledNode: rootNode)), for: memberSymbol)
                        }
                    } else {
                        if let result = processMemberSymbol(symbol, node: node, rootNode: rootNode) {
                            entry.setMemberSymbols(for: result)
                        }
                    }
                }
            } catch {
                print(error)
            }
        }

        entry.setSymbolsByOffset(symbolsByOffset)

        entry.setDemangledNodeBySymbol(demangledNodeBySymbol)

        return entry
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
        var node = node
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
            guard let parent = node.parent, parent.children.first === node else { return nil }
            node = parent
            traits.insert(.isStorage)
            fallthrough
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
        let typeNode = Node(kind: .type, child: node)
        let typeName = typeNode.print(using: .interfaceTypeBuilderOnly)
        if let typeKind = node.kind.typeKind {
//            typeInfoByName[typeName] = .init(name: typeName, kind: typeKind)
//            entry[memberKind, default: [:]][typeName, default: [:]][typeNode, default: []].append(IndexedSymbol(DemangledSymbol(symbol: symbol, demangledNode: rootNode)))
            return .init(memberKind: memberKind, typeName: typeName, typeNode: typeNode, typeInfo: .init(name: typeName, kind: typeKind), indexedSymbol: IndexedSymbol(DemangledSymbol(symbol: symbol, demangledNode: rootNode)))
        }
        return nil
    }

    fileprivate struct ProcessGlobalSymbolResult: Sendable {
        let kind: GlobalKind
        let indexedSymbol: IndexedSymbol
    }

    private func processGlobalSymbol(_ symbol: Symbol, node: Node, rootNode: Node) -> ProcessGlobalSymbolResult? {
        switch node.kind {
        case .function:
            return .init(kind: .function, indexedSymbol: IndexedSymbol(DemangledSymbol(symbol: symbol, demangledNode: rootNode)))
        case .variable:
            guard let parent = node.parent, parent.children.first === node else { return nil }
            let isStorage = node.parent?.isAccessor == false
            return .init(kind: .variable(isStorage: isStorage), indexedSymbol: IndexedSymbol(DemangledSymbol(symbol: symbol, demangledNode: rootNode)))
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
        if let symbols = entry(in: machO)?.symbolsByKind.values.flatMap({ $0 }) {
            return symbols.mapWrappedValues()
        } else {
            return []
        }
    }

    public func symbolsByKind<MachO: MachORepresentableWithCache>(in machO: MachO) -> OrderedDictionary<Node.Kind, [DemangledSymbol]> {
        if let symbols = entry(in: machO)?.symbolsByKind {
            return symbols.mapValues { $0.mapWrappedValues() }
        } else {
            return [:]
        }
    }

    public func typeInfo<MachO: MachORepresentableWithCache>(for name: String, in machO: MachO) -> TypeInfo? {
        return entry(in: machO)?.typeInfoByName[name]
    }

    public func symbols<MachO: MachORepresentableWithCache>(of kinds: Node.Kind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.symbolsByKind[$0] ?? [] }.reduce(into: []) { $0 += $1.mapWrappedValues() }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.memberSymbolsByKind[$0]?.values.flatMap { $0.values.flatMap { $0 } } ?? [] }.reduce(into: []) { $0 += $1.mapWrappedValues() }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.memberSymbolsByKind[$0]?[name]?.values.flatMap { $0 } ?? [] }.reduce(into: []) { $0 += $1.mapWrappedValues() }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, node: Node, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.memberSymbolsByKind[$0]?[name]?[node] ?? [] }.reduce(into: []) { $0 += $1.mapWrappedValues() }
    }

    public func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., excluding names: borrowing Set<String>, in machO: MachO) -> OrderedDictionary<Node, OrderedDictionary<MemberKind, [DemangledSymbol]>> {
        let filtered = kinds.reduce(into: [:]) { $0[$1] = entry(in: machO)?.memberSymbolsByKind[$1]?.filter { !names.contains($0.key) } ?? [:] }

        var result: OrderedDictionary<Node, OrderedDictionary<MemberKind, [DemangledSymbol]>> = [:]
        for (kind, memberSymbols) in filtered {
            for (_, symbols) in memberSymbols {
                for (node, symbols) in symbols {
                    result[node, default: [:]][kind, default: []].append(contentsOf: symbols.mapWrappedValues())
                }
            }
        }
        return result
    }

    public func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.methodDescriptorMemberSymbolsByKind[$0]?.values.flatMap { $0.values.flatMap { $0 } } ?? [] }.reduce(into: []) { $0 += $1.mapWrappedValues() }
    }

    public func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.methodDescriptorMemberSymbolsByKind[$0]?[name]?.values.flatMap { $0 } ?? [] }.reduce(into: []) { $0 += $1.mapWrappedValues() }
    }

    public func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.protocolWitnessMemberSymbolsByKind[$0]?.values.flatMap { $0.values.flatMap { $0 } } ?? [] }.reduce(into: []) { $0 += $1.mapWrappedValues() }
    }

    public func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.protocolWitnessMemberSymbolsByKind[$0]?[name]?.values.flatMap { $0 } ?? [] }.reduce(into: []) { $0 += $1.mapWrappedValues() }
    }

    public func globalSymbols<MachO: MachORepresentableWithCache>(of kinds: GlobalKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.globalSymbolsByKind[$0] ?? [] }.reduce(into: []) { $0 += $1.mapWrappedValues() }
    }

    public func allOpaqueTypeDescriptorSymbols<MachO: MachORepresentableWithCache>(in machO: MachO) -> OrderedDictionary<Node, DemangledSymbol>? {
        return entry(in: machO)?.opaqueTypeDescriptorSymbolByNode.mapValues {
            return $0.wrappedValue
        }
    }

    public func opaqueTypeDescriptorSymbol<MachO: MachORepresentableWithCache>(for node: Node, in machO: MachO) -> DemangledSymbol? {
        return entry(in: machO)?.opaqueTypeDescriptorSymbolByNode[node].map {
            $0.isConsumed = true
            return $0.wrappedValue
        }
    }

    package func symbols<MachO: MachORepresentableWithCache>(for offset: Int, in machO: MachO) -> Symbols? {
        if let symbols = entry(in: machO)?.symbolsByOffset[offset], !symbols.isEmpty {
            return .init(offset: offset, symbols: symbols)
        } else {
            return nil
        }
    }

    package func demangledNode<MachO: MachORepresentableWithCache>(for symbol: Symbol, in machO: MachO) -> Node? {
        guard let cacheEntry = entry(in: machO) else { return nil }
        if let node = cacheEntry.demangledNodeBySymbol[symbol] {
            return node
        } else if let node = try? demangleAsNode(symbol.name) {
            cacheEntry.setDemangledNode(node, for: symbol)
            return node
        } else {
            return nil
        }
    }

    public func prepare<MachO: MachORepresentableWithCache>(in machO: MachO) {
        _ = entry(in: machO)
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
//             .modifyAccessor,
//             .modify2Accessor,
//             .readAccessor,
//             .read2Accessor,
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
        return isKind(of: .getter, .setter, .modifyAccessor, .modify2Accessor, .readAccessor, .read2Accessor)
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

extension Sequence where Element == SymbolIndexStore.IndexedSymbol {
    func mapWrappedValues() -> [DemangledSymbol] {
        var results: [DemangledSymbol] = []
        for indexedSymbol in self {
            indexedSymbol.isConsumed = true
            results.append(indexedSymbol.wrappedValue)
        }
        return results
    }
}
