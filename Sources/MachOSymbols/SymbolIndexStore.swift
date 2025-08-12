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

    package enum DesciptorKind: String, Hashable, CaseIterable {
        case anonymous
        case associatedConformance
        case associatedType
        case baseConformance
        case `extension`
        case method
        case module
        case nominalType
        case opaqueType
        case property
        case `protocol`
        case protocolConformance
        case protocolRequirementsBase
        case protocolSelfConformance
        case reflectionMetadataAssocType
        case reflectionMetadataBuiltin
        case reflectionMetadataField
        case reflectionMetadataSuperclass

        var nodeKind: Node.Kind {
            switch self {
            case .anonymous:
                return .anonymousDescriptor
            case .associatedConformance:
                return .associatedConformanceDescriptor
            case .associatedType:
                return .associatedTypeDescriptor
            case .baseConformance:
                return .baseConformanceDescriptor
            case .extension:
                return .extensionDescriptor
            case .method:
                return .methodDescriptor
            case .module:
                return .moduleDescriptor
            case .nominalType:
                return .nominalTypeDescriptor
            case .opaqueType:
                return .opaqueTypeDescriptor
            case .property:
                return .propertyDescriptor
            case .protocol:
                return .protocolDescriptor
            case .protocolConformance:
                return .protocolConformanceDescriptor
            case .protocolRequirementsBase:
                return .protocolRequirementsBaseDescriptor
            case .protocolSelfConformance:
                return .protocolSelfConformanceDescriptor
            case .reflectionMetadataAssocType:
                return .reflectionMetadataAssocTypeDescriptor
            case .reflectionMetadataBuiltin:
                return .reflectionMetadataBuiltinDescriptor
            case .reflectionMetadataField:
                return .reflectionMetadataFieldDescriptor
            case .reflectionMetadataSuperclass:
                return .reflectionMetadataSuperclassDescriptor
            }
        }
    }

    package static let shared = SymbolIndexStore()

    private override init() { super.init() }

    package struct Entry {
        fileprivate var memberSymbolsByKind: [MemberKind: [String: [Symbol]]] = [:]
        fileprivate var descriptorSymbolsByKind: [DesciptorKind: [Symbol]] = [:]
        fileprivate var symbolsByKind: [Node.Kind: [Symbol]] = [:]
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
                if node.kind == .static, let firstChild = node.children.first, firstChild.kind.isMember {
                    processMemberSymbol(symbol, node: firstChild, isStatic: true, in: &entry)
                } else if node.kind.isMember {
                    processMemberSymbol(symbol, node: node, isStatic: false, in: &entry)
                } else if let descriptorKind = node.kind.descriptorKind {
                    entry.descriptorSymbolsByKind[descriptorKind, default: []].append(symbol)
                }

                entry.symbolsByKind[node.kind, default: []].append(symbol)
                
            } catch {
                print(error)
            }
        }
        return entry
    }

    private func processMemberSymbol(_ symbol: Symbol, node: Node, isStatic: Bool, in entry: inout Entry) {
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

            entry.memberSymbolsByKind[kind, default: [:]][globalTypeNode.print(using: .interface), default: []].append(symbol)
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
    
    
    package func descriptorSymbols<MachO: MachORepresentableWithCache>(of kind: DesciptorKind, in machO: MachO) -> [Symbol] {
        if let symbols = entry(in: machO)?.descriptorSymbolsByKind[kind] {
            return symbols
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
}

extension Node.Kind {
    fileprivate var isMember: Bool {
        switch self {
        case .allocator,
             .function,
             .getter,
             .setter,
             .modifyAccessor:
            return true
        default:
            return false
        }
    }

    fileprivate var isDescriptor: Bool {
        switch self {
        case .associatedConformanceDescriptor,
             .associatedTypeDescriptor,
             .baseConformanceDescriptor,
             .extensionDescriptor,
             .methodDescriptor,
             .moduleDescriptor,
             .nominalTypeDescriptor,
             .opaqueTypeDescriptor,
             .propertyDescriptor,
             .protocolDescriptor,
             .protocolConformanceDescriptor,
             .protocolRequirementsBaseDescriptor,
             .protocolSelfConformanceDescriptor,
             .reflectionMetadataAssocTypeDescriptor,
             .reflectionMetadataBuiltinDescriptor,
             .reflectionMetadataFieldDescriptor,
             .reflectionMetadataSuperclassDescriptor:
            return true
        default:
            return false
        }
    }

    fileprivate var descriptorKind: SymbolIndexStore.DesciptorKind? {
        switch self {
        case .anonymousDescriptor:
            return .anonymous
        case .associatedConformanceDescriptor:
            return .associatedConformance
        case .associatedTypeDescriptor:
            return .associatedType
        case .baseConformanceDescriptor:
            return .baseConformance
        case .extensionDescriptor:
            return .extension
        case .methodDescriptor:
            return .method
        case .moduleDescriptor:
            return .module
        case .nominalTypeDescriptor:
            return .nominalType
        case .opaqueTypeDescriptor:
            return .opaqueType
        case .propertyDescriptor:
            return .property
        case .protocolDescriptor:
            return .protocol
        case .protocolConformanceDescriptor:
            return .protocolConformance
        case .protocolRequirementsBaseDescriptor:
            return .protocolRequirementsBase
        case .protocolSelfConformanceDescriptor:
            return .protocolSelfConformance
        case .reflectionMetadataAssocTypeDescriptor:
            return .reflectionMetadataAssocType
        case .reflectionMetadataBuiltinDescriptor:
            return .reflectionMetadataBuiltin
        case .reflectionMetadataFieldDescriptor:
            return .reflectionMetadataField
        case .reflectionMetadataSuperclassDescriptor:
            return .reflectionMetadataSuperclass
        default:
            return nil
        }
    }
}
