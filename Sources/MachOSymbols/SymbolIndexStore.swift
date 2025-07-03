import Foundation
import MachOKit
import MachOExtensions
import Demangle
import OrderedCollections
import Utilities
import MachOCaches

package final class SymbolIndexStore: MachOCache<SymbolIndexStore.Entry> {
    package enum IndexKind: Hashable, CaseIterable, CustomStringConvertible {
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

    private override init() {
        super.init()
    }

    package struct Entry {
        fileprivate var symbolsByKind: [IndexKind: [String: [Symbol]]] = [:]
    }

    package override func buildEntry<MachO>(for machO: MachO) -> Entry? where MachO: MachORepresentableWithCache {
        var entry = Entry()

        var symbols: OrderedDictionary<String, Symbol> = [:]

        for symbol in machO.symbols where symbol.name.isSwiftSymbol {
            symbols[symbol.name] = .init(offset: symbol.offset, stringValue: symbol.name)
        }

        for exportedSymbol in machO.exportedSymbols where exportedSymbol.name.isSwiftSymbol {
            if let offset = exportedSymbol.offset, symbols[exportedSymbol.name] == nil {
                symbols[exportedSymbol.name] = .init(offset: offset, stringValue: exportedSymbol.name)
            }
        }

        for symbol in symbols.values {
            do {
                let node = try demangleAsNode(symbol.stringValue)

                func perform(_ node: Node, isStatic: Bool) {
                    guard let firstChild = node.children.first else { return }

                    func processTypeNode(_ typeNode: Node?, inExtension: Bool) {
                        guard let typeNode = typeNode else { return }

                        let kind: IndexKind
                        switch firstChild.kind {
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

                        entry.symbolsByKind[kind, default: [:]][globalTypeNode.print(using: .interface), default: []].append(symbol)
                    }

                    switch firstChild.kind {
                    case .function,
                         .allocator:
                        if firstChild.children.first?.kind == .extension {
                            processTypeNode(firstChild.children.first?.children.at(1), inExtension: true)
                        } else {
                            processTypeNode(firstChild.children.first, inExtension: false)
                        }
                    case .getter,
                         .setter,
                         .modifyAccessor:
                        guard let variableNode = firstChild.children.first, variableNode.kind == .variable else { return }
                        if variableNode.children.first?.kind == .extension {
                            processTypeNode(variableNode.children.first?.children.at(1), inExtension: true)
                        } else {
                            processTypeNode(variableNode.children.first, inExtension: false)
                        }
                    default:
                        break
                    }
                }

                if let staticNode = node.children.first, staticNode.kind == .static {
                    perform(staticNode, isStatic: true)
                } else {
                    perform(node, isStatic: false)
                }

            } catch {
                print(error)
            }
        }
        return entry
    }

    package func symbols<MachO: MachORepresentableWithCache>(of kind: IndexKind, for name: String, in machO: MachO) -> [Symbol] {
        if let symbol = entry(in: machO)?.symbolsByKind[kind]?[name] {
            return symbol
        } else {
            return []
        }
    }
}
