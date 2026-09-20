import Demangling
import SwiftInspection
import SwiftThunkAnalysis

/// Joins an `ObjCAncestorOverrideTable` — the members whose `To` thunk is the
/// IMP of a selector an ObjC ancestor also implements — onto already-built
/// member definitions (evolution proposal `objc-ancestor-override-recovery`).
/// Shared by `TypeDefinition` (a Swift class with ObjC ancestry) and
/// `ExtensionDefinition` (an `@objc @implementation` class body): the table
/// is keyed by implementation symbol name, and every member definition knows
/// its own symbols, so the join is a lookup per member.
package enum ObjCAncestorOverrideApplication {
    /// Applies the table and returns how many members it marked.
    @discardableResult
    package static func apply(
        _ table: ObjCAncestorOverrideTable,
        functions: inout [FunctionDefinition],
        variables: inout [VariableDefinition],
        subscripts: inout [SubscriptDefinition],
        staticFunctions: inout [FunctionDefinition],
        staticVariables: inout [VariableDefinition],
        staticSubscripts: inout [SubscriptDefinition],
        allocators: inout [FunctionDefinition]
    ) -> Int {
        var markedCount = 0
        markedCount += apply(table, toFunctions: &functions)
        markedCount += apply(table, toFunctions: &staticFunctions)
        markedCount += apply(table, toVariables: &variables)
        markedCount += apply(table, toVariables: &staticVariables)
        markedCount += apply(table, toSubscripts: &subscripts)
        markedCount += apply(table, toSubscripts: &staticSubscripts)
        for index in allocators.indices {
            guard allocators[index].objcAncestorOverride == nil,
                  let override = table.override(forAllocatorSymbolNamed: allocators[index].symbol.name)
            else { continue }
            allocators[index].objcAncestorOverride = override
            markedCount += 1
        }
        if ObjCAncestorOverrides.infersOverridesFromSelectorNames, !table.unattributedOverriddenMethods.isEmpty {
            markedCount += inferFromSelectorNames(
                table,
                functions: &functions,
                variables: &variables,
                subscripts: &subscripts,
                staticFunctions: &staticFunctions,
                staticVariables: &staticVariables,
                allocators: &allocators
            )
        }
        return markedCount
    }

    /// The optional third tier: an overriding ObjC method tied to no symbol
    /// (its body was inlined) goes to the ONE still-unmarked member whose
    /// name is the importer's spelling of its selector. Subscripts take no
    /// part — an ObjC subscript selector (`objectAtIndexedSubscript:`) is
    /// never the spelling of a Swift `subscript`.
    private static func inferFromSelectorNames(
        _ table: ObjCAncestorOverrideTable,
        functions: inout [FunctionDefinition],
        variables: inout [VariableDefinition],
        subscripts: inout [SubscriptDefinition],
        staticFunctions: inout [FunctionDefinition],
        staticVariables: inout [VariableDefinition],
        allocators: inout [FunctionDefinition]
    ) -> Int {
        enum MemberKey: Hashable {
            case function(Int), staticFunction(Int), variable(Int), staticVariable(Int), allocator(Int)
        }
        var shapes: [(key: MemberKey, shape: ObjCMemberShape)] = []
        func collect(_ definitions: [FunctionDefinition], key: (Int) -> MemberKey) {
            for (index, definition) in definitions.enumerated() where definition.objcAncestorOverride == nil {
                if let shape = ObjCMemberShape(demangledSymbol: definition.node.materialize()) {
                    shapes.append((key(index), shape))
                }
            }
        }
        func collect(_ definitions: [VariableDefinition], key: (Int) -> MemberKey) {
            for (index, definition) in definitions.enumerated() where definition.objcAncestorOverride == nil {
                for accessor in definition.accessors {
                    if let shape = ObjCMemberShape(demangledSymbol: accessor.symbol.demangledNode.materialize()) {
                        shapes.append((key(index), shape))
                    }
                }
            }
        }
        collect(functions, key: MemberKey.function)
        collect(staticFunctions, key: MemberKey.staticFunction)
        collect(allocators, key: MemberKey.allocator)
        collect(variables, key: MemberKey.variable)
        collect(staticVariables, key: MemberKey.staticVariable)

        let inferred = table.inferredOverrides(forMemberShapes: shapes)
        for (key, override) in inferred {
            switch key {
            case .function(let index): functions[index].objcAncestorOverride = override
            case .staticFunction(let index): staticFunctions[index].objcAncestorOverride = override
            case .variable(let index): variables[index].objcAncestorOverride = override
            case .staticVariable(let index): staticVariables[index].objcAncestorOverride = override
            case .allocator(let index): allocators[index].objcAncestorOverride = override
            }
        }
        return inferred.count
    }

    private static func apply(_ table: ObjCAncestorOverrideTable, toFunctions definitions: inout [FunctionDefinition]) -> Int {
        var markedCount = 0
        for index in definitions.indices {
            guard definitions[index].objcAncestorOverride == nil,
                  let override = table.override(forMemberSymbolNamed: definitions[index].symbol.name)
            else { continue }
            definitions[index].objcAncestorOverride = override
            markedCount += 1
        }
        return markedCount
    }

    private static func apply(_ table: ObjCAncestorOverrideTable, toVariables definitions: inout [VariableDefinition]) -> Int {
        var markedCount = 0
        for index in definitions.indices {
            guard definitions[index].objcAncestorOverride == nil,
                  let override = firstOverride(in: table, forAccessors: definitions[index].accessors)
            else { continue }
            definitions[index].objcAncestorOverride = override
            markedCount += 1
        }
        return markedCount
    }

    private static func apply(_ table: ObjCAncestorOverrideTable, toSubscripts definitions: inout [SubscriptDefinition]) -> Int {
        var markedCount = 0
        for index in definitions.indices {
            guard definitions[index].objcAncestorOverride == nil,
                  let override = firstOverride(in: table, forAccessors: definitions[index].accessors)
            else { continue }
            definitions[index].objcAncestorOverride = override
            markedCount += 1
        }
        return markedCount
    }

    /// A property or subscript overrides when ANY of its accessors does — the
    /// getter's `To` thunk is the common case, a `set`-only override the rare one.
    private static func firstOverride(in table: ObjCAncestorOverrideTable, forAccessors accessors: [Accessor]) -> ObjCAncestorOverride? {
        for accessor in accessors {
            if let override = table.override(forMemberSymbolNamed: accessor.symbol.name) {
                return override
            }
        }
        return nil
    }
}
