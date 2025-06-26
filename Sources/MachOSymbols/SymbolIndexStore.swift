import Foundation
import MachOKit
import MachOExtensions
import Demangle
import OrderedCollections

package final class SymbolIndexStore {
    package enum IndexKind: Hashable {
        package enum SubKind: Hashable, CaseIterable {
            case function
            case functionInExtension
            case staticFunction
            case staticFunctionInExtension
            case variable
            case variableInExtension
            case staticVariable
            case staticVariableInExtension
        }

        case `enum`(SubKind)
        case `struct`(SubKind)
        case `class`(SubKind)
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

    private var indexEntryByIdentifier: [MachOTargetIdentifier: IndexEntry] = [:]

    private func removeIndexs(for machOImage: MachOImage) {
        let identifier = MachOTargetIdentifier.image(machOImage.ptr)
        removeIndexs(for: identifier)
    }

    private func removeIndexs(for machOFile: MachOFile) {
        let identifier = MachOTargetIdentifier.file(machOFile.imagePath)
        removeIndexs(for: identifier)
    }

    private func removeIndexs(for identifier: MachOTargetIdentifier) {
        indexEntryByIdentifier.removeValue(forKey: identifier)
    }

    @discardableResult
    private func startIndexingIfNeeded(for machOImage: MachOImage) -> Bool {
        let identifier = MachOTargetIdentifier.image(machOImage.ptr)
        return startIndexingIfNeeded(for: identifier, in: machOImage)
    }

    @discardableResult
    private func startIndexingIfNeeded(for machOFile: MachOFile) -> Bool {
        let identifier = MachOTargetIdentifier.file(machOFile.imagePath)
        return startIndexingIfNeeded(for: identifier, in: machOFile)
    }

    @discardableResult
    private func startIndexingIfNeeded<MachO: MachORepresentableWithCache>(for identifier: MachOTargetIdentifier, in machO: MachO) -> Bool {
        if let existedEntry = indexEntryByIdentifier[identifier], existedEntry.isIndexed {
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
                func perform(_ node: Node, isStatic: Bool) {
                    if let functionNode = node.children.first, functionNode.kind == .function {
                        if let structureNode = functionNode.children.first, structureNode.kind == .structure {
                            let typeNode = Node(kind: .global) {
                                Node(kind: .type, child: structureNode)
                            }
                            entry.symbolsByKind[isStatic ? .struct(.staticFunction) : .struct(.function), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
                        } else if let enumNode = functionNode.children.first, enumNode.kind == .enum {
                            let typeNode = Node(kind: .global) {
                                Node(kind: .type, child: enumNode)
                            }
                            entry.symbolsByKind[isStatic ? .enum(.staticFunction) : .enum(.function), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
                        } else if let extensionNode = functionNode.children.first, extensionNode.kind == .extension {
                            if let structureNode = extensionNode.children.at(1), structureNode.kind == .structure {
                                let typeNode = Node(kind: .global) {
                                    Node(kind: .type, child: structureNode)
                                }
                                entry.symbolsByKind[isStatic ? .struct(.staticFunctionInExtension) : .struct(.functionInExtension), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
                            } else if let enumNode = extensionNode.children.at(1), enumNode.kind == .enum {
                                let typeNode = Node(kind: .global) {
                                    Node(kind: .type, child: enumNode)
                                }
                                entry.symbolsByKind[isStatic ? .enum(.staticFunctionInExtension) : .enum(.functionInExtension), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
                            }
                        }
                    } else if let propertyNode = node.children.first, propertyNode.kind == .getter || propertyNode.kind == .setter || propertyNode.kind == .modifyAccessor, let variableNode = propertyNode.children.first, variableNode.kind == .variable {
                        if let structureNode = variableNode.children.first, structureNode.kind == .structure {
                            let typeNode = Node(kind: .global) {
                                Node(kind: .type, child: structureNode)
                            }
                            entry.symbolsByKind[isStatic ? .struct(.staticVariable) : .struct(.variable), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
                        } else if let enumNode = variableNode.children.first, enumNode.kind == .enum {
                            let typeNode = Node(kind: .global) {
                                Node(kind: .type, child: enumNode)
                            }
                            entry.symbolsByKind[isStatic ? .enum(.staticVariable) : .enum(.variable), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
                        } else if let extensionNode = variableNode.children.first, extensionNode.kind == .extension {
                            if let structureNode = extensionNode.children.at(1), structureNode.kind == .structure {
                                let typeNode = Node(kind: .global) {
                                    Node(kind: .type, child: structureNode)
                                }
                                entry.symbolsByKind[isStatic ? .struct(.staticVariableInExtension) : .struct(.variableInExtension), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
                            } else if let enumNode = extensionNode.children.at(1), enumNode.kind == .enum {
                                let typeNode = Node(kind: .global) {
                                    Node(kind: .type, child: enumNode)
                                }
                                entry.symbolsByKind[isStatic ? .enum(.staticVariableInExtension) : .enum(.variableInExtension), default: [:]][typeNode.print(using: .interface), default: []].append(symbol)
                            }
                        }
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
        indexEntryByIdentifier[identifier] = entry
        return true
    }

    package func symbols(of kind: IndexKind, for name: String, in machOImage: MachOImage) -> [Symbol] {
        let identifier = MachOTargetIdentifier.image(machOImage.ptr)
        startIndexingIfNeeded(for: identifier, in: machOImage)
        return symbols(of: kind, for: name, with: identifier, in: machOImage)
    }

    package func symbols(of kind: IndexKind, for name: String, in machOFile: MachOFile) -> [Symbol] {
        let identifier = MachOTargetIdentifier.file(machOFile.imagePath)
        startIndexingIfNeeded(for: identifier, in: machOFile)
        return symbols(of: kind, for: name, with: identifier, in: machOFile)
    }

    private func symbols<MachO: MachORepresentableWithCache>(of kind: IndexKind, for name: String, with identifier: MachOTargetIdentifier, in machO: MachO) -> [Symbol] {
        if let symbol = indexEntryByIdentifier[identifier]?.symbolsByKind[kind]?[name] {
            return symbol
        } else {
            return []
        }
    }
}
