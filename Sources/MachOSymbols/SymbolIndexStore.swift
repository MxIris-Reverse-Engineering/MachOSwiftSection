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

    package static let shared = SymbolIndexStore()

    private override init() { super.init() }

    package struct Entry {
        fileprivate var symbolsByKind: OrderedDictionary<Node.Kind, [Symbol]> = [:]
        fileprivate var memberSymbolsByKind: OrderedDictionary<MemberKind, OrderedDictionary<String, [Symbol]>> = [:]
        fileprivate var methodDescriptorMemberSymbolsByKind: OrderedDictionary<MemberKind, OrderedDictionary<String, [Symbol]>> = [:]
        fileprivate var protocolWitnessMemberSymbolsByKind: OrderedDictionary<MemberKind, OrderedDictionary<String, [Symbol]>> = [:]
    }

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

                func processMemberSymbols(for node: Node, in entry: inout OrderedDictionary<MemberKind, OrderedDictionary<String, [Symbol]>>) {
                    if node.kind == .static, let firstChild = node.children.first, firstChild.kind.isMember {
                        processMemberSymbol(symbol, node: firstChild, isStatic: true, in: &entry)
                    } else if node.kind.isMember {
                        processMemberSymbol(symbol, node: node, isStatic: false, in: &entry)
                    }
                }

                if let firstChild = node.children.first {
                    if node.kind == .methodDescriptor {
                        processMemberSymbols(for: firstChild, in: &entry.methodDescriptorMemberSymbolsByKind)
                    } else if node.kind == .protocolWitness {
                        processMemberSymbols(for: firstChild, in: &entry.protocolWitnessMemberSymbolsByKind)
                    } else if !firstChild.kind.isMember {
                        processMemberSymbols(for: node, in: &entry.memberSymbolsByKind)
                    }
                }

                entry.symbolsByKind[node.kind, default: []].append(symbol)

            } catch {
                print(error)
            }
        }
        return entry
    }

    private func processMemberSymbol(_ symbol: Symbol, node: Node, isStatic: Bool, in entry: inout OrderedDictionary<MemberKind, OrderedDictionary<String, [Symbol]>>) {
        func processTypeNode(_ typeNode: Node?, inExtension: Bool) {
            guard let typeNode = typeNode else { return }

            let kind: MemberKind
            switch node.kind {
            case .allocator:
                kind = inExtension ? .allocatorInExtension : .allocator
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

            entry[kind, default: [:]][globalTypeNode.print(using: .interface), default: []].append(symbol)
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

    package func symbols<MachO: MachORepresentableWithCache>(of kind: Node.Kind, in machO: MachO) -> [Symbol] {
        if let symbols = entry(in: machO)?.symbolsByKind[kind] {
            return symbols
        } else {
            return []
        }
    }

    package func memberSymbols<MachO: MachORepresentableWithCache>(of kind: MemberKind, in machO: MachO) -> [Symbol] {
        if let symbol = entry(in: machO)?.memberSymbolsByKind[kind]?.values.flatMap({ $0 }) {
            return symbol
        } else {
            return []
        }
    }

    package func memberSymbols<MachO: MachORepresentableWithCache>(of kind: MemberKind, for name: String, in machO: MachO) -> [Symbol] {
        if let symbol = entry(in: machO)?.memberSymbolsByKind[kind]?[name] {
            return symbol
        } else {
            return []
        }
    }

    package func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kind: MemberKind, in machO: MachO) -> [Symbol] {
        if let symbol = entry(in: machO)?.methodDescriptorMemberSymbolsByKind[kind]?.values.flatMap({ $0 }) {
            return symbol
        } else {
            return []
        }
    }
    
    
    package func methodDescriptorMemberSymbols<MachO: MachORepresentableWithCache>(of kind: MemberKind, for name: String, in machO: MachO) -> [Symbol] {
        if let symbol = entry(in: machO)?.methodDescriptorMemberSymbolsByKind[kind]?[name] {
            return symbol
        } else {
            return []
        }
    }

    
    package func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kind: MemberKind, in machO: MachO) -> [Symbol] {
        if let symbol = entry(in: machO)?.protocolWitnessMemberSymbolsByKind[kind]?.values.flatMap({ $0 }) {
            return symbol
        } else {
            return []
        }
    }
    
    package func protocolWitnessMemberSymbols<MachO: MachORepresentableWithCache>(of kind: MemberKind, for name: String, in machO: MachO) -> [Symbol] {
        if let symbol = entry(in: machO)?.protocolWitnessMemberSymbolsByKind[kind]?[name] {
            return symbol
        } else {
            return []
        }
    }
}

extension Node.Kind {
    fileprivate var isMember: Bool {
        switch self {
        case .allocator,
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
}
