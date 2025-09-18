import Foundation
import MachOKit
import MachOExtensions
import Demangle
import OrderedCollections
import Utilities
@_spi(Private) import MachOCaches

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
        case `subscript`(inExtension: Bool, isStatic: Bool)
        case variable(inExtension: Bool, isStatic: Bool, isStorage: Bool)
        case function(inExtension: Bool, isStatic: Bool)

        package static var allCases: [SymbolIndexStore.MemberKind] = [
            .allocator(inExtension: false),
            .allocator(inExtension: true),
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
                return "allocator" + (inExtension ? " (in extension)" : "")
            case .subscript(inExtension: let inExtension, isStatic: let isStatic):
                return "subscript" + (isStatic ? " static" : "") + (inExtension ? " (in extension)" : "")
            case .variable(inExtension: let inExtension, isStatic: let isStatic, isStorage: let isStorage):
                return "variable" + (isStatic ? " static" : "") + (isStorage ? " (storage)" : "") + (inExtension ? " (in extension)" : "")
            case .function(inExtension: let inExtension, isStatic: let isStatic):
                return "function" + (isStatic ? " static" : "") + (inExtension ? " (in extension)" : "")
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
        fileprivate var typeInfoByName: [String: TypeInfo] = [:]
    }

    package typealias MemberSymbols = OrderedDictionary<String, [DemangledSymbol]>

    package static let shared = SymbolIndexStore()

    override private init() { super.init() }

    override package func buildEntry<MachO>(for machO: MachO) -> Entry? where MachO: MachORepresentableWithCache {
        var entry = Entry()

        var symbols: OrderedDictionary<String, Symbol> = [:]

        for symbol in machO.symbols where symbol.name.isSwiftSymbol {
            var offset = symbol.offset
            if let cache = machO.cache {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
            }
            symbols[symbol.name] = .init(offset: symbol.offset, stringValue: symbol.name)
        }

        for exportedSymbol in machO.exportedSymbols where exportedSymbol.name.isSwiftSymbol {
            if var offset = exportedSymbol.offset, symbols[exportedSymbol.name] == nil {
                offset += machO.startOffset
                symbols[exportedSymbol.name] = .init(offset: offset, stringValue: exportedSymbol.name)
            }
        }

        for symbol in symbols.values {
            do {
                let globalNode = try demangleAsNode(symbol.stringValue)
                guard let node = globalNode.children.first else { continue }

                if node.kind == .methodDescriptor, let firstChild = node.children.first {
                    processMemberSymbol(symbol, node: firstChild, globalNode: globalNode, in: &entry.methodDescriptorMemberSymbolsByKind, typeInfoByName: &entry.typeInfoByName)
                } else if node.kind == .protocolWitness, let firstChild = node.children.first {
                    processMemberSymbol(symbol, node: firstChild, globalNode: globalNode, in: &entry.protocolWitnessMemberSymbolsByKind, typeInfoByName: &entry.typeInfoByName)
                } else if node.kind == .mergedFunction, let secondChild = globalNode.children.second {
                    processMemberSymbol(symbol, node: secondChild, globalNode: globalNode, in: &entry.memberSymbolsByKind, typeInfoByName: &entry.typeInfoByName)
                } else {
                    processMemberSymbol(symbol, node: node, globalNode: globalNode, in: &entry.memberSymbolsByKind, typeInfoByName: &entry.typeInfoByName)
                }

                entry.symbolsByKind[node.kind, default: []].append(.init(symbol: symbol, demangledNode: globalNode))

            } catch {
                print(error)
            }
        }
        return entry
    }

    private func processMemberSymbol(_ symbol: Symbol, node: Node, globalNode: Node, in innerEntry: inout OrderedDictionary<MemberKind, MemberSymbols>, typeInfoByName: inout [String: TypeInfo]) {
        if node.kind == .static, let firstChild = node.children.first, firstChild.kind.isMember {
            processMemberSymbol(symbol, node: firstChild, globalNode: globalNode, traits: [.isStatic], in: &innerEntry, typeInfoByName: &typeInfoByName)
        } else if node.kind.isMember {
            processMemberSymbol(symbol, node: node, globalNode: globalNode, traits: [], in: &innerEntry, typeInfoByName: &typeInfoByName)
        }
    }

    private func processMemberSymbol(_ symbol: Symbol, node: Node, globalNode: Node, traits: MemberKind.Traits, in entry: inout OrderedDictionary<MemberKind, MemberSymbols>, typeInfoByName: inout [String: TypeInfo]) {
        var traits = traits
        var node = node
        switch node.kind {
        case .allocator:
            guard var first = node.children.first else { return }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            processMemberSymbol(symbol, node: first, globalNode: globalNode, memberKind: .allocator(inExtension: traits.contains(.inExtension)), in: &entry, typeInfoByName: &typeInfoByName)
        case .function:
            guard var first = node.children.first else { return }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            processMemberSymbol(symbol, node: first, globalNode: globalNode, memberKind: .function(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic)), in: &entry, typeInfoByName: &typeInfoByName)
        case .variable:
            guard let parent = node.parent, parent.children.first == node else { return }
            node = parent
            traits.insert(.isStorage)
            fallthrough
        case .getter,
             .setter,
             .modifyAccessor,
             .modify2Accessor,
             .readAccessor,
             .read2Accessor:
            guard let variableNode = node.children.first, variableNode.kind == .variable, var first = variableNode.children.first else { return }
            if first.kind == .extension, let type = first.children.at(1) {
                traits.insert(.inExtension)
                first = type
            }
            processMemberSymbol(symbol, node: first, globalNode: globalNode, memberKind: .variable(inExtension: traits.contains(.inExtension), isStatic: traits.contains(.isStatic), isStorage: traits.contains(.isStorage)), in: &entry, typeInfoByName: &typeInfoByName)
        default:
            break
        }
    }

    private func processMemberSymbol(_ symbol: Symbol, node: Node, globalNode: Node, memberKind: MemberKind, in entry: inout OrderedDictionary<MemberKind, MemberSymbols>, typeInfoByName: inout [String: TypeInfo]) {
        let globalTypeNode = Node(kind: .global) {
            Node(kind: .type, child: node)
        }

        let typeName = globalTypeNode.print(using: .interfaceTypeBuilderOnly)

        if let typeKind = node.kind.typeKind {
            typeInfoByName[typeName] = .init(name: typeName, kind: typeKind)
            entry[memberKind, default: [:]][typeName, default: []].append(.init(symbol: symbol, demangledNode: globalNode))
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
}

private extension Node.Kind {
    var isMember: Bool {
        switch self {
        case .allocator,
             .deallocator,
             .function,
             .getter,
             .setter,
             .modifyAccessor,
             .methodDescriptor,
             .protocolWitness,
             .variable:
            return true
        default:
            return false
        }
    }

    var typeKind: SymbolIndexStore.TypeInfo.Kind? {
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
