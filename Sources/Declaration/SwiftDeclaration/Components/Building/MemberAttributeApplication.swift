import Demangling
import MachOSwiftSection
@_spi(Internals) import MachOSymbols

/// Cross-references `@objc` / `@nonobjc` / `distributed` thunk attribute
/// members (pre-extracted and bucketed by parent type name inside
/// `SymbolIndexStore`) with already-built member definitions, appending the
/// matching attribute to each affected member. Shared by `TypeDefinition`
/// and `ExtensionDefinition` — the sweep unwraps extension contexts when it
/// buckets a thunk, so an extension's members are filed under the extended
/// type's name and node, and one lookup serves both containers.
package enum MemberAttributeApplication {
    package static let thunkKindsAndAttributes: [(thunkKind: Node.Kind, attribute: SwiftAttribute)] = [
        (.objCAttribute, .objc),
        (.nonObjCAttribute, .nonobjc),
        (.distributedThunk, .distributed),
    ]

    package static func applyThunkAttributes(
        symbolIndexStore: SymbolIndexStore,
        typeName: String,
        typeNode: NodeReference,
        in machO: some MachORepresentableWithCache,
        functions: inout [FunctionDefinition],
        variables: inout [VariableDefinition],
        staticFunctions: inout [FunctionDefinition],
        staticVariables: inout [VariableDefinition],
        allocators: inout [FunctionDefinition]
    ) {
        for (thunkKind, attribute) in thunkKindsAndAttributes {
            // Node-matched: the member-name matching below is string-based,
            // so a same-named private sibling's thunks must never reach it
            // (issue #115's family).
            let members = symbolIndexStore.thunkAttributeMembers(of: thunkKind, for: typeName, node: typeNode, in: machO)
            for member in members {
                if member.isStatic {
                    apply(attribute, toFunctionNamed: member.memberName, in: &staticFunctions)
                    apply(attribute, toVariableNamed: member.memberName, in: &staticVariables)
                } else {
                    apply(attribute, toFunctionNamed: member.memberName, in: &functions)
                    apply(attribute, toVariableNamed: member.memberName, in: &variables)
                    if member.isInit {
                        apply(attribute, toEveryAllocatorIn: &allocators)
                    }
                }
            }
        }
    }

    package static func apply(_ attribute: SwiftAttribute, toFunctionNamed name: String, in definitions: inout [FunctionDefinition]) {
        for definitionIndex in definitions.indices {
            if definitions[definitionIndex].name == name && !definitions[definitionIndex].attributes.contains(attribute) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }

    package static func apply(_ attribute: SwiftAttribute, toVariableNamed name: String, in definitions: inout [VariableDefinition]) {
        for definitionIndex in definitions.indices {
            if definitions[definitionIndex].name == name && !definitions[definitionIndex].attributes.contains(attribute) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }

    package static func apply(_ attribute: SwiftAttribute, toEveryAllocatorIn definitions: inout [FunctionDefinition]) {
        for definitionIndex in definitions.indices {
            if !definitions[definitionIndex].attributes.contains(attribute) {
                definitions[definitionIndex].attributes.append(attribute)
            }
        }
    }
}
