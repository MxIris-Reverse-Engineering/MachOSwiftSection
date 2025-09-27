import Foundation
import MachOKit
import MachOExtensions
import Demangle
import OrderedCollections
import Utilities
@_spi(Private) import MachOCaches
import Dependencies

package final class SymbolIndexStore: MachOCache<SymbolIndexStore.Entry> {
    package enum MemberKind: Hashable, CaseIterable, CustomStringConvertible {
        package struct Traits: OptionSet, Hashable {
            package let rawValue: Int
            package init(rawValue: Int) {
                self.rawValue = rawValue
            }

            package static let isStatic = Traits(rawValue: 1 << 0)
            package static let isStorage = Traits(rawValue: 1 << 1)
            package static let inExtension = Traits(rawValue: 1 << 2)
        }

        case allocator(inExtension: Bool)
        case deallocator
        case constructor(inExtension: Bool)
        case destructor
        case `subscript`(inExtension: Bool, isStatic: Bool)
        case variable(inExtension: Bool, isStatic: Bool, isStorage: Bool)
        case function(inExtension: Bool, isStatic: Bool)

        package static let allCases: [SymbolIndexStore.MemberKind] = [
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

        package var description: String {
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

    package enum GlobalKind: Hashable, CaseIterable, CustomStringConvertible {
        case variable(isStorage: Bool)
        case function

        package static let allCases: [SymbolIndexStore.GlobalKind] = [
            .variable(isStorage: false),
            .variable(isStorage: true),
            .function,
        ]

        package var description: String {
            switch self {
            case .variable(isStorage: let isStorage):
                return (isStorage ? "Stored " : "") + "Global Variable"
            case .function:
                return "Global Function"
            }
        }
    }

    package struct TypeInfo {
        package enum Kind {
            case `enum`
            case `struct`
            case `class`
            case `protocol`
            case typeAlias
        }

        package let name: String
        package let kind: Kind
    }

    package struct Entry {
        fileprivate var symbolsByKind: OrderedDictionary<Node.Kind, [DemangledSymbol]> = [:]
        fileprivate var memberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]
        fileprivate var methodDescriptorMemberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]
        fileprivate var protocolWitnessMemberSymbolsByKind: OrderedDictionary<MemberKind, MemberSymbols> = [:]
        fileprivate var globalSymbolsByKind: OrderedDictionary<GlobalKind, [DemangledSymbol]> = [:]
        fileprivate var typeInfoByName: [String: TypeInfo] = [:]
        fileprivate var opaqueTypeDescriptorSymbolByNode: OrderedDictionary<Node, DemangledSymbol> = [:]
    }

    package typealias MemberSymbols = OrderedDictionary<String, [DemangledSymbol]>

    package static let shared = SymbolIndexStore()

    private override init() { super.init() }

    package override func buildEntry<MachO>(for machO: MachO) -> Entry? where MachO: MachORepresentableWithCache {
        var entry = Entry()

        var symbols: OrderedDictionary<String, Symbol> = [:]

        for symbol in machO.symbols where symbol.name.isSwiftSymbol {
            var offset = symbol.offset
            if let cache = machO.cache, offset != 0, machO is MachOFile {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
            }
            symbols[symbol.name] = .init(offset: offset, name: symbol.name, nlist: symbol.nlist)
        }

        for exportedSymbol in machO.exportedSymbols where exportedSymbol.name.isSwiftSymbol {
            if var offset = exportedSymbol.offset, symbols[exportedSymbol.name] == nil {
                offset += machO.startOffset
                symbols[exportedSymbol.name] = .init(offset: offset, name: exportedSymbol.name)
            }
        }

        for symbol in symbols.values {
            do {
                let rootNode = try demangleAsNode(symbol.name)

                guard rootNode.isKind(of: .global), let node = rootNode.children.first else { continue }

                entry.symbolsByKind[node.kind, default: []].append(.init(symbol: symbol, demangledNode: rootNode))

                if rootNode.isGlobal {
                    if !symbol.isExternal {
                        processGlobalSymbol(symbol, node: node, rootNode: rootNode, in: &entry.globalSymbolsByKind)
                    }
                } else {
                    if node.kind == .methodDescriptor, let firstChild = node.children.first {
                        processMemberSymbol(symbol, node: firstChild, rootNode: rootNode, in: &entry.methodDescriptorMemberSymbolsByKind, typeInfoByName: &entry.typeInfoByName)
                    } else if node.kind == .protocolWitness, let firstChild = node.children.first {
                        processMemberSymbol(symbol, node: firstChild, rootNode: rootNode, in: &entry.protocolWitnessMemberSymbolsByKind, typeInfoByName: &entry.typeInfoByName)
                    } else if node.kind == .mergedFunction, let secondChild = rootNode.children.second {
                        processMemberSymbol(symbol, node: secondChild, rootNode: rootNode, in: &entry.memberSymbolsByKind, typeInfoByName: &entry.typeInfoByName)
                    } else if node.kind == .opaqueTypeDescriptor, let firstChild = node.children.first, firstChild.kind == .opaqueReturnTypeOf, let memberSymbol = firstChild.children.first {
                        processOpaqueTypeDescriptorSymbol(symbol, node: memberSymbol, rootNode: rootNode, in: &entry.opaqueTypeDescriptorSymbolByNode)
                    } else {
                        processMemberSymbol(symbol, node: node, rootNode: rootNode, in: &entry.memberSymbolsByKind, typeInfoByName: &entry.typeInfoByName)
                    }
                }
            } catch {
                print(error)
            }
        }
        return entry
    }

    private func processOpaqueTypeDescriptorSymbol(_ symbol: Symbol, node: Node, rootNode: Node, in entry: inout OrderedDictionary<Node, DemangledSymbol>) {
        guard symbol.offset > 0 else { return }
        entry[node] = .init(symbol: symbol, demangledNode: rootNode)
    }
    
    private func processGlobalSymbol(_ symbol: Symbol, node: Node, rootNode: Node, in entry: inout OrderedDictionary<GlobalKind, [DemangledSymbol]>) {
        switch node.kind {
        case .function:
            entry[.function, default: []].append(.init(symbol: symbol, demangledNode: rootNode))
        case .variable:
            guard let parent = node.parent, parent.children.first === node else { return }
            let isStorage = node.parent?.isAccessor == false
            entry[.variable(isStorage: isStorage), default: []].append(.init(symbol: symbol, demangledNode: rootNode))
        case .getter,
             .setter:
            if let variableNode = node.children.first, variableNode.kind == .variable {
                processGlobalSymbol(symbol, node: variableNode, rootNode: rootNode, in: &entry)
            }
        default:
            break
        }
    }

    private func processMemberSymbol(_ symbol: Symbol, node: Node, rootNode: Node, in innerEntry: inout OrderedDictionary<MemberKind, MemberSymbols>, typeInfoByName: inout [String: TypeInfo]) {
        if node.kind == .static, let firstChild = node.children.first, firstChild.kind.isMember {
            processMemberSymbol(symbol, node: firstChild, rootNode: rootNode, traits: [.isStatic], in: &innerEntry, typeInfoByName: &typeInfoByName)
        } else if node.kind.isMember {
            processMemberSymbol(symbol, node: node, rootNode: rootNode, traits: [], in: &innerEntry, typeInfoByName: &typeInfoByName)
        }
    }

    private func processMemberSymbol(_ symbol: Symbol, node: Node, rootNode: Node, traits: MemberKind.Traits, in entry: inout OrderedDictionary<MemberKind, MemberSymbols>, typeInfoByName: inout [String: TypeInfo]) {
        var traits = traits
        var node = node
        switch node.kind {
        case .allocator:
            guard var first = node.children.first else { return }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .allocator(inExtension: traits.contains(.inExtension)), in: &entry, typeInfoByName: &typeInfoByName)
        case .deallocator:
            guard let first = node.children.first else { return }
            processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .deallocator, in: &entry, typeInfoByName: &typeInfoByName)
        case .constructor:
            guard var first = node.children.first else { return }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .constructor(inExtension: traits.contains(.inExtension)), in: &entry, typeInfoByName: &typeInfoByName)
        case .destructor:
            guard let first = node.children.first else { return }
            processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .destructor, in: &entry, typeInfoByName: &typeInfoByName)
        case .function:
            guard var first = node.children.first else { return }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .function(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic)), in: &entry, typeInfoByName: &typeInfoByName)
        case .variable:
            guard let parent = node.parent, parent.children.first === node else { return }
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
                processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .variable(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic), isStorage: traits.contains(.isStorage)), in: &entry, typeInfoByName: &typeInfoByName)
            } else if let subscriptNode = node.children.first, subscriptNode.kind == .subscript, var first = subscriptNode.children.first {
                if first.kind == .extension, let type = first.children.at(1) {
                    traits.insert(.inExtension)
                    first = type
                }
                processMemberSymbol(symbol, node: first, rootNode: rootNode, memberKind: .subscript(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic)), in: &entry, typeInfoByName: &typeInfoByName)
            }
        default:
            break
        }
    }

    private func processMemberSymbol(_ symbol: Symbol, node: Node, rootNode: Node, memberKind: MemberKind, in entry: inout OrderedDictionary<MemberKind, MemberSymbols>, typeInfoByName: inout [String: TypeInfo]) {
        let globalTypeNode = Node(kind: .global) {
            Node(kind: .type, child: node)
        }

        let typeName = globalTypeNode.print(using: .interfaceTypeBuilderOnly)

        if let typeKind = node.kind.typeKind {
            typeInfoByName[typeName] = .init(name: typeName, kind: typeKind)
            entry[memberKind, default: [:]][typeName, default: []].append(.init(symbol: symbol, demangledNode: rootNode))
        } else {
//                print(#function)
//                print(globalTypeNode)
//                print(typeName)
//                print(globalNode)
//                print(globalNode.print(using: .default))
//                print("---------------------------")
        }
    }

    package func allSymbols<MachO: MachORepresentableWithCache>(in machO: MachO) -> [DemangledSymbol] {
        if let symbols = entry(in: machO)?.symbolsByKind.values.flatMap({ $0 }) {
            return symbols
        } else {
            return []
        }
    }

    package func typeInfo<MachO: MachORepresentableWithCache>(for name: String, in machO: MachO) -> TypeInfo? {
        return entry(in: machO)?.typeInfoByName[name]
    }

    package func symbols<MachO: MachORepresentableWithCache>(of kinds: Node.Kind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.symbolsByKind[$0] ?? [] }.reduce(into: []) { $0 += $1 }
    }

    package func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.memberSymbolsByKind[$0]?.values.flatMap { $0 } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    package func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.memberSymbolsByKind[$0]?[name] ?? [] }.reduce(into: []) { $0 += $1 }
    }

    package func memberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., excluding names: borrowing Set<String>, in machO: MachO) -> OrderedDictionary<String, OrderedDictionary<MemberKind, [DemangledSymbol]>> {
        let filtered = kinds.reduce(into: [:]) { $0[$1] = entry(in: machO)?.memberSymbolsByKind[$1]?.filter { !names.contains($0.key) } ?? [:] }
        var result: OrderedDictionary<String, OrderedDictionary<MemberKind, [DemangledSymbol]>> = [:]
        for (kind, memberSymbols) in filtered {
            for (name, symbols) in memberSymbols {
                result[name, default: [:]][kind] = symbols
            }
        }
        return result
    }

    package func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.methodDescriptorMemberSymbolsByKind[$0]?.values.flatMap { $0 } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    package func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.methodDescriptorMemberSymbolsByKind[$0]?[name] ?? [] }.reduce(into: []) { $0 += $1 }
    }

    package func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., excluding names: borrowing Set<String>, in machO: MachO) -> OrderedDictionary<String, [DemangledSymbol]> {
        return kinds.map { entry(in: machO)?.methodDescriptorMemberSymbolsByKind[$0]?.filter { !names.contains($0.key) } ?? [:] }.reduce(into: [:]) { $0.merge($1) { $0 + $1 } }
    }

    package func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.protocolWitnessMemberSymbolsByKind[$0]?.values.flatMap { $0 } ?? [] }.reduce(into: []) { $0 += $1 }
    }

    package func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., for name: String, in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.protocolWitnessMemberSymbolsByKind[$0]?[name] ?? [] }.reduce(into: []) { $0 += $1 }
    }

    package func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kinds: MemberKind..., excluding names: borrowing Set<String>, in machO: MachO) -> OrderedDictionary<String, [DemangledSymbol]> {
        return kinds.map { entry(in: machO)?.protocolWitnessMemberSymbolsByKind[$0]?.filter { !names.contains($0.key) } ?? [:] }.reduce(into: [:]) { $0.merge($1) { $0 + $1 } }
    }

    package func globalSymbols<MachO: MachORepresentableWithCache>(of kinds: GlobalKind..., in machO: MachO) -> [DemangledSymbol] {
        return kinds.map { entry(in: machO)?.globalSymbolsByKind[$0] ?? [] }.reduce(into: []) { $0 += $1 }
    }
    
    package func opaqueTypeDescriptorSymbol<MachO: MachORepresentableWithCache>(for node: Node, in machO: MachO) -> DemangledSymbol? {
        return entry(in: machO)?.opaqueTypeDescriptorSymbolByNode[node]
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

extension DependencyValues {
    package var symbolIndexStore: SymbolIndexStore {
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
        guard let nlist, let flags = nlist.flags, let type = flags.type else { return false }
        return flags.contains(.ext) && type == .undf
    }
}
