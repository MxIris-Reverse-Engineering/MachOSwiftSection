@_spi(Internals) import MachOSymbols
import OrderedCollections

extension Definition {
    func addSymbol(_ symbol: DemangledSymbol, memberSymbolsByKind: inout OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>, inExtension: Bool) {
        let node = symbol.demangledNode
        if node.contains(.variable) {
            if node.contains(.static) {
                if node.isStoredVariable {
                    memberSymbolsByKind[.variable(inExtension: inExtension, isStatic: true, isStorage: true), default: []].append(symbol)
                } else {
                    memberSymbolsByKind[.variable(inExtension: inExtension, isStatic: true, isStorage: false), default: []].append(symbol)
                }
            } else {
                memberSymbolsByKind[.variable(inExtension: inExtension, isStatic: false, isStorage: false), default: []].append(symbol)
            }
        } else if node.contains(.allocator) {
            memberSymbolsByKind[.allocator(inExtension: inExtension), default: []].append(symbol)
        } else if node.contains(.function) {
            if node.contains(.static) {
                memberSymbolsByKind[.function(inExtension: inExtension, isStatic: true), default: []].append(symbol)
            } else {
                memberSymbolsByKind[.function(inExtension: inExtension, isStatic: false), default: []].append(symbol)
            }
        } else if node.contains(.subscript) {
            if node.contains(.static) {
                memberSymbolsByKind[.subscript(inExtension: inExtension, isStatic: true), default: []].append(symbol)
            } else {
                memberSymbolsByKind[.subscript(inExtension: inExtension, isStatic: false), default: []].append(symbol)
            }
        }
    }
}

extension MutableDefinition {
    func setDefintions(for memberSymbolsByKind: OrderedDictionary<SymbolIndexStore.MemberKind, [DemangledSymbol]>, inExtension: Bool) {
        for (kind, memberSymbols) in memberSymbolsByKind {
            switch kind {
            case .variable(inExtension, let isStatic, false):
                if isStatic {
                    staticVariables = DefinitionBuilder.variables(for: memberSymbols, fieldNames: [], isGlobalOrStatic: true)
                } else {
                    variables = DefinitionBuilder.variables(for: memberSymbols, fieldNames: [], isGlobalOrStatic: false)
                }
            case .allocator:
                allocators = DefinitionBuilder.allocators(for: memberSymbols)
            case .function(inExtension, let isStatic):
                if isStatic {
                    staticFunctions = DefinitionBuilder.functions(for: memberSymbols, isGlobalOrStatic: true)
                } else {
                    functions = DefinitionBuilder.functions(for: memberSymbols, isGlobalOrStatic: false)
                }
            case .subscript(inExtension, let isStatic):
                if isStatic {
                    staticSubscripts = DefinitionBuilder.subscripts(for: memberSymbols, isStatic: true)
                } else {
                    subscripts = DefinitionBuilder.subscripts(for: memberSymbols, isStatic: false)
                }
            default:
                break
            }
        }
    }
}
