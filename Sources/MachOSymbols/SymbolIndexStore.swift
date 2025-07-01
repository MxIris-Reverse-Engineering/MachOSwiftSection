import Foundation
import MachOKit
import MachOExtensions
import Demangle
import OrderedCollections
import Utilities

package final class SymbolIndexStore {
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

    private let memoryPressureMonitor = MemoryPressureMonitor()

    private init() {
        memoryPressureMonitor.memoryWarningHandler = { [weak self] in
            self?.indexEntryByIdentifier.removeAll()
        }

        memoryPressureMonitor.memoryCriticalHandler = { [weak self] in
            self?.indexEntryByIdentifier.removeAll()
        }

        memoryPressureMonitor.startMonitoring()
    }

    private struct IndexEntry {
        var isIndexed: Bool = false
        var symbolsByKind: [IndexKind: [String: [Symbol]]] = [:]
    }

    private var indexEntryByIdentifier: [AnyHashable: IndexEntry] = [:]


    @discardableResult
    package func startIndexingIfNeeded<MachO: MachORepresentableWithCache>(in machO: MachO) -> Bool {
        if let existedEntry = indexEntryByIdentifier[machO.identifier], existedEntry.isIndexed {
            return true
        }
        var entry = IndexEntry()

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
                var demangler = Demangler(scalars: symbol.stringValue.unicodeScalars)
                let node = try demangler.demangleSymbol()
//                func perform(_ node: Node, isStatic: Bool) {
//                    if let functionNode = node.children.first, functionNode.kind == .function {
//                        if let structureNode = functionNode.children.first, structureNode.kind == .structure {
//                            let typeNode = Node(kind: .global) {
//                                Node(kind: .type, child: structureNode)
//                            }
//                            entry.symbolsByKind[isStatic ? .struct(.staticFunction) : .struct(.function), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
//                        } else if let enumNode = functionNode.children.first, enumNode.kind == .enum {
//                            let typeNode = Node(kind: .global) {
//                                Node(kind: .type, child: enumNode)
//                            }
//                            entry.symbolsByKind[isStatic ? .enum(.staticFunction) : .enum(.function), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
//                        } else if let extensionNode = functionNode.children.first, extensionNode.kind == .extension {
//                            if let structureNode = extensionNode.children.at(1), structureNode.kind == .structure {
//                                let typeNode = Node(kind: .global) {
//                                    Node(kind: .type, child: structureNode)
//                                }
//                                entry.symbolsByKind[isStatic ? .struct(.staticFunctionInExtension) : .struct(.functionInExtension), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
//                            } else if let enumNode = extensionNode.children.at(1), enumNode.kind == .enum {
//                                let typeNode = Node(kind: .global) {
//                                    Node(kind: .type, child: enumNode)
//                                }
//                                entry.symbolsByKind[isStatic ? .enum(.staticFunctionInExtension) : .enum(.functionInExtension), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
//                            }
//                        }
//                    } else if let propertyNode = node.children.first, propertyNode.kind == .getter || propertyNode.kind == .setter || propertyNode.kind == .modifyAccessor, let variableNode = propertyNode.children.first, variableNode.kind == .variable {
//                        if let structureNode = variableNode.children.first, structureNode.kind == .structure {
//                            let typeNode = Node(kind: .global) {
//                                Node(kind: .type, child: structureNode)
//                            }
//                            entry.symbolsByKind[isStatic ? .struct(.staticVariable) : .struct(.variable), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
//                        } else if let enumNode = variableNode.children.first, enumNode.kind == .enum {
//                            let typeNode = Node(kind: .global) {
//                                Node(kind: .type, child: enumNode)
//                            }
//                            entry.symbolsByKind[isStatic ? .enum(.staticVariable) : .enum(.variable), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
//                        } else if let extensionNode = variableNode.children.first, extensionNode.kind == .extension {
//                            if let structureNode = extensionNode.children.at(1), structureNode.kind == .structure {
//                                let typeNode = Node(kind: .global) {
//                                    Node(kind: .type, child: structureNode)
//                                }
//                                entry.symbolsByKind[isStatic ? .struct(.staticVariableInExtension) : .struct(.variableInExtension), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
//                            } else if let enumNode = extensionNode.children.at(1), enumNode.kind == .enum {
//                                let typeNode = Node(kind: .global) {
//                                    Node(kind: .type, child: enumNode)
//                                }
//                                entry.symbolsByKind[isStatic ? .enum(.staticVariableInExtension) : .enum(.variableInExtension), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
//                            }
//                        }
//                    }
//                }

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
        entry.isIndexed = true
        indexEntryByIdentifier[machO.identifier] = entry
        return true
    }

    package func symbols<MachO: MachORepresentableWithCache>(of kind: IndexKind, for name: String, in machO: MachO) -> [Symbol] {
        startIndexingIfNeeded(in: machO)
        if let symbol = indexEntryByIdentifier[machO.identifier]?.symbolsByKind[kind]?[name] {
            return symbol
        } else {
            return []
        }
    }
}
