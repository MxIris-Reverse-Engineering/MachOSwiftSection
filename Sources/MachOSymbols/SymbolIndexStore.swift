import Foundation
import MachOKit
import MachOExtensions
import Demangle
import OrderedCollections
import Utilities
@_spi(Private) import MachOCaches

package final class SymbolIndexStore: MachOCache<SymbolIndexStore.Entry> {
    package enum MemberKind: Hashable, CaseIterable, CustomStringConvertible {
        case allocator
        case allocatorInExtension
        case deallocator
        case function
        case functionInExtension
        case staticFunction
        case staticFunctionInExtension
        case variable
        case variableInExtension
        case staticVariable
        case staticVariableInExtension

        package var description: String {
            switch self {
            case .allocator:
                "Allocators"
            case .allocatorInExtension:
                "Allocators In Extensions"
            case .deallocator:
                "Deallocators"
            case .function:
                "Functions"
            case .functionInExtension:
                "Functions In Extensions"
            case .staticFunction:
                "Static Functions"
            case .staticFunctionInExtension:
                "Static Functions In Extensions"
            case .variable:
                "Variables"
            case .variableInExtension:
                "Variables In Extensions"
            case .staticVariable:
                "Static Variables"
            case .staticVariableInExtension:
                "Static Variables In Extensions"
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

    private override init() { super.init() }

    package override func buildEntry<MachO>(for machO: MachO) -> Entry? where MachO: MachORepresentableWithCache {
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

                func processMemberSymbols(for node: Node, in innerEntry: inout OrderedDictionary<MemberKind, MemberSymbols>, typeInfoByName: inout [String: TypeInfo]) {
                    if node.kind == .static, let firstChild = node.children.first, firstChild.kind.isMember {
                        processMemberSymbol(symbol, node: firstChild, globalNode: globalNode, isStatic: true, in: &innerEntry, typeInfoByName: &typeInfoByName)
                    } else if node.kind.isMember {
                        processMemberSymbol(symbol, node: node, globalNode: globalNode, isStatic: false, in: &innerEntry, typeInfoByName: &typeInfoByName)
                    }
                }

                if node.kind == .methodDescriptor, let firstChild = node.children.first {
                    processMemberSymbols(for: firstChild, in: &entry.methodDescriptorMemberSymbolsByKind, typeInfoByName: &entry.typeInfoByName)
                } else if node.kind == .protocolWitness, let firstChild = node.children.first {
                    processMemberSymbols(for: firstChild, in: &entry.protocolWitnessMemberSymbolsByKind, typeInfoByName: &entry.typeInfoByName)
                } else {
                    processMemberSymbols(for: node, in: &entry.memberSymbolsByKind, typeInfoByName: &entry.typeInfoByName)
                }

                entry.symbolsByKind[node.kind, default: []].append(.init(symbol: symbol, demangledNode: globalNode))

            } catch {
                print(error)
            }
        }
        return entry
    }

    private func processMemberSymbol(_ symbol: Symbol, node: Node, globalNode: Node, isStatic: Bool, in entry: inout OrderedDictionary<MemberKind, MemberSymbols>, typeInfoByName: inout [String: TypeInfo]) {
        func processTypeNode(_ typeNode: Node?, inExtension: Bool) {
            guard let typeNode = typeNode else { return }

            let kind: MemberKind
            switch node.kind {
            case .allocator:
                kind = inExtension ? .allocatorInExtension : .allocator
            case .deallocator:
                kind = .deallocator
            case .function:
                if isStatic {
                    kind = inExtension ? .staticFunctionInExtension : .staticFunction
                } else {
                    kind = inExtension ? .functionInExtension : .function
                }
            case .getter,
                 .setter,
                 .modifyAccessor:
                if isStatic {
                    kind = inExtension ? .staticVariableInExtension : .staticVariable
                } else {
                    kind = inExtension ? .variableInExtension : .variable
                }
            default:
                return
            }

            let globalTypeNode = Node(kind: .global) {
                Node(kind: .type, child: typeNode)
            }

            let typeName = globalTypeNode.print(using: .interfaceTypeBuilderOnly)

            if let typeKind = typeNode.kind.typeKind {
                typeInfoByName[typeName] = .init(name: typeName, kind: typeKind)
                entry[kind, default: [:]][typeName, default: []].append(.init(symbol: symbol, demangledNode: globalNode))
            } else {
//                print(#function)
//                print(globalTypeNode)
//                print(typeName)
//                print(globalNode)
//                print(globalNode.print(using: .default))
//                print("---------------------------")
            }
        }

        switch node.kind {
        case .function,
             .allocator:
            if node.children.first?.kind == .extension {
                processTypeNode(node.children.first?.children.at(1), inExtension: true)
            } else {
                processTypeNode(node.children.first, inExtension: false)
            }
        case .getter,
             .setter,
             .modifyAccessor:
            guard let variableNode = node.children.first, variableNode.kind == .variable else { return }
            if variableNode.children.first?.kind == .extension {
                processTypeNode(variableNode.children.first?.children.at(1), inExtension: true)
            } else {
                processTypeNode(variableNode.children.first, inExtension: false)
            }
        default:
            break
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

extension Node.Kind {
    fileprivate var isMember: Bool {
        switch self {
        case .allocator,
             .deallocator,
             .function,
             .getter,
             .setter,
             .modifyAccessor,
             .methodDescriptor,
             .protocolWitness:
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
