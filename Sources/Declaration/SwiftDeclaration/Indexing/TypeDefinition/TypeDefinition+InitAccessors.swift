@_spi(Internals) import Demangling
@_spi(Internals) import MachOSymbols
import SwiftInspection

/// SE-0400 init accessor recovery, a step of `TypeDefinition.index(in:)`
/// (evolution proposal `init-accessor-recovery`): which fields each init
/// accessor is inferred to initialize, read off the type's stored properties
/// by the rules of `InitAccessorFieldInference`. Runs once the member
/// variables are built and the fields known, and before `orderedMembers`
/// copies the members' values.
extension TypeDefinition {
    /// - Parameter fields: the type's fields, which `index(in:)` assigns to
    ///   `fields` only later.
    func recoverInitAccessorFieldNames(fields: [FieldDefinition]) {
        guard variables.contains(where: \.hasInitAccessor) else { return }
        let fieldsByName = Dictionary(fields.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for index in variables.indices where variables[index].hasInitAccessor {
            guard let declaredTypeNode = WrappedPropertyRecovery.declaredTypeNode(of: variables[index]) else { continue }
            variables[index].initializedFieldNames = InitAccessorFieldInference.initializedFieldNames(
                ofPropertyNamed: variables[index].name,
                declaredTypeNode: declaredTypeNode
            ) { fieldName in
                fieldsByName[fieldName].map { InitAccessorFieldInference.StoredField(name: $0.name, typeNode: $0.typeNode.materialize()) }
            }
        }
    }
}
