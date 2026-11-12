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
    /// The type compared with a field is the one the init accessor's own
    /// symbol spells, not the declaration's — that is the getter's, which
    /// can keep an older mangling (`InitAccessorFieldInference`). The dump
    /// reads the same symbol, so the two agree.
    ///
    /// - Parameter fields: the type's fields, which `index(in:)` assigns to
    ///   `fields` only later.
    func recoverInitAccessorFieldNames(fields: [FieldDefinition]) {
        guard variables.contains(where: \.hasInitAccessor) else { return }
        let fieldsByName = Dictionary(fields.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        for index in variables.indices {
            guard let initAccessor = variables[index].accessors.last(where: { $0.kind == .initAccessor }) else { continue }
            variables[index].initializedFieldNames = InitAccessorFieldInference.initializedFieldNames(ofInitAccessorSymbol: initAccessor.symbol.demangledNode) { fieldName in
                fieldsByName[fieldName].map { InitAccessorFieldInference.StoredField(name: $0.name, typeNode: $0.typeNode.materialize()) }
            }
        }
    }
}
