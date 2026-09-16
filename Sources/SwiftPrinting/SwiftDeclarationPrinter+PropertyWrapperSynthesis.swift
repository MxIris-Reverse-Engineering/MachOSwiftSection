import SwiftDeclaration
import Demangling

/// The members the compiler synthesizes for a property declared with a
/// property wrapper (`@Wrapper var x: Int`): the backing storage field `_x`
/// of the wrapper type and, when the wrapper has a `projectedValue`, the
/// computed `$x`. The source declares only `x`, so the interface hides both —
/// but only once the evidence is complete: a stored `_x` whose type the
/// installed `PropertyWrapperTypeResolving` recognizes as a property wrapper,
/// and a member variable `x`. A hand-written `_y` behind a computed `y` keeps
/// rendering: nothing says `_y`'s type wraps anything. dump is untouched; it
/// shows what the records say.
extension SwiftDeclarationPrinter {
    struct SynthesizedPropertyWrapperMembers: Sendable {
        /// Backing-storage field names (`_x`).
        var fieldNames: Set<String> = []
        /// Projection variable names (`$x`).
        var variableNames: Set<String> = []

        static var none: SynthesizedPropertyWrapperMembers { SynthesizedPropertyWrapperMembers() }

        func contains(_ member: OrderedMember) -> Bool {
            guard case .variable(let variable) = member else { return false }
            return variableNames.contains(variable.name)
        }
    }

    /// The synthesized members of `definition`, empty without a resolver or
    /// for anything but a type (an extension cannot declare stored properties).
    func synthesizedPropertyWrapperMembers(of definition: some Definition) -> SynthesizedPropertyWrapperMembers {
        guard let typeDefinition = definition as? TypeDefinition,
              let propertyWrapperTypeResolver
        else { return .none }
        var synthesized = SynthesizedPropertyWrapperMembers()
        for field in typeDefinition.fields where field.name.hasPrefix("_") && field.name.count > 1 {
            let wrappedPropertyName = String(field.name.dropFirst())
            guard typeDefinition.variables.contains(where: { $0.name == wrappedPropertyName }) else { continue }
            guard let wrapperTypeNode = Self.nominalTypeNode(ofFieldType: field.typeNode.materialize()),
                  propertyWrapperTypeResolver.isPropertyWrapperType(wrapperTypeNode)
            else { continue }
            synthesized.fieldNames.insert(field.name)
            synthesized.variableNames.insert("$" + wrappedPropertyName)
        }
        return synthesized
    }

    /// The `.type`-wrapped nominal a field's type node names, generic
    /// arguments stripped — the shape a `TypeName.node` has, so the resolver
    /// can look it up structurally. `nil` for anything that is not a plain or
    /// bound-generic struct / class / enum.
    static func nominalTypeNode(ofFieldType typeNode: Node) -> Node? {
        guard typeNode.kind == .type, let inner = typeNode.firstChild else { return nil }
        switch inner.kind {
        case .structure, .class, .enum:
            return typeNode
        case .boundGenericStructure, .boundGenericClass, .boundGenericEnum:
            guard let nominal = inner.firstChild, nominal.kind == .type else { return nil }
            return nominal
        default:
            return nil
        }
    }
}
