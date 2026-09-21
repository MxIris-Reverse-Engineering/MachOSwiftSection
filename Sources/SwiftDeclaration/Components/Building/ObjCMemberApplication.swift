import Demangling
import SwiftInspection
import SwiftThunkAnalysis

/// Joins an `ObjCMemberTable` — the class's ObjC method table tied to its
/// Swift members — onto already-built member definitions (evolution
/// proposals `objc-ancestor-override-recovery` and
/// `objc-member-selector-recovery`). Shared by `TypeDefinition` (a Swift
/// class with ObjC ancestry) and `ExtensionDefinition` (an `@objc
/// @implementation` class body, or a Swift extension whose `@objc` members
/// compiled to a category): the table is keyed by implementation symbol
/// name, and every member definition knows its own symbols, so the join is
/// a lookup per member. A member the table knows is `@objc` — the attribute
/// is added when the thunk symbols (stripped in OS frameworks) did not
/// already supply it.
package enum ObjCMemberApplication {
    /// Applies the table and returns how many members it tied.
    @discardableResult
    package static func apply(
        _ table: ObjCMemberTable,
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
            guard allocators[index].objcMember == nil,
                  let member = table.member(forAllocatorSymbolNamed: allocators[index].symbol.name)
            else { continue }
            allocators[index].objcMember = member
            addObjCAttribute(to: &allocators[index].attributes)
            markedCount += 1
        }
        if ObjCMembers.infersOverridesFromSelectorNames, !table.unattributedOverriddenMethods.isEmpty {
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
        _ table: ObjCMemberTable,
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
            for (index, definition) in definitions.enumerated() where definition.objcMember == nil {
                if let shape = ObjCMemberShape(demangledSymbol: definition.node.materialize()) {
                    shapes.append((key(index), shape))
                }
            }
        }
        func collect(_ definitions: [VariableDefinition], key: (Int) -> MemberKey) {
            for (index, definition) in definitions.enumerated() where definition.objcMember == nil {
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
        for (key, member) in inferred {
            switch key {
            case .function(let index):
                functions[index].objcMember = member
                addObjCAttribute(to: &functions[index].attributes)
            case .staticFunction(let index):
                staticFunctions[index].objcMember = member
                addObjCAttribute(to: &staticFunctions[index].attributes)
            case .variable(let index):
                variables[index].objcMember = member
                addObjCAttribute(to: &variables[index].attributes)
            case .staticVariable(let index):
                staticVariables[index].objcMember = member
                addObjCAttribute(to: &staticVariables[index].attributes)
            case .allocator(let index):
                allocators[index].objcMember = member
                addObjCAttribute(to: &allocators[index].attributes)
            }
        }
        return inferred.count
    }

    private static func addObjCAttribute(to attributes: inout [SwiftAttribute]) {
        if !attributes.contains(.objc) {
            attributes.append(.objc)
        }
    }

    private static func apply(_ table: ObjCMemberTable, toFunctions definitions: inout [FunctionDefinition]) -> Int {
        var markedCount = 0
        for index in definitions.indices {
            guard definitions[index].objcMember == nil,
                  let member = table.member(forMemberSymbolNamed: definitions[index].symbol.name)
            else { continue }
            definitions[index].objcMember = member
            addObjCAttribute(to: &definitions[index].attributes)
            markedCount += 1
        }
        return markedCount
    }

    private static func apply(_ table: ObjCMemberTable, toVariables definitions: inout [VariableDefinition]) -> Int {
        var markedCount = 0
        for index in definitions.indices {
            guard definitions[index].objcMember == nil,
                  let member = firstMember(in: table, forAccessors: definitions[index].accessors)
            else { continue }
            definitions[index].objcMember = member
            addObjCAttribute(to: &definitions[index].attributes)
            markedCount += 1
        }
        return markedCount
    }

    private static func apply(_ table: ObjCMemberTable, toSubscripts definitions: inout [SubscriptDefinition]) -> Int {
        var markedCount = 0
        for index in definitions.indices {
            guard definitions[index].objcMember == nil,
                  let member = firstMember(in: table, forAccessors: definitions[index].accessors)
            else { continue }
            definitions[index].objcMember = member
            addObjCAttribute(to: &definitions[index].attributes)
            markedCount += 1
        }
        return markedCount
    }

    /// A property or subscript is tied through ANY of its accessors — the
    /// getter first, because an explicit selector on a property is the
    /// getter's (`@objc(name)` names the getter, the setter follows as
    /// `setName:`); a member tied through its setter alone keeps the fact
    /// with the explicit-selector flag cleared, since `setName:` is not what
    /// the attribute would spell.
    private static func firstMember(in table: ObjCMemberTable, forAccessors accessors: [Accessor]) -> ObjCMember? {
        if let getter = accessors.first(where: { $0.kind == .getter }), let member = table.member(forMemberSymbolNamed: getter.symbol.name) {
            return member
        }
        for accessor in accessors {
            if let member = table.member(forMemberSymbolNamed: accessor.symbol.name) {
                return member.withoutExplicitSelector()
            }
        }
        return nil
    }
}
