import SwiftDeclaration
import Demangling

/// The members the compiler synthesizes for a property declared with a
/// property wrapper (`@Wrapper var x: Int`): the backing storage field `_x`
/// of the wrapper type and, when the wrapper has a `projectedValue`, the
/// computed `$x`. The source declares only `x`, so the interface hides both
/// and prints the wrapper as `x`'s attribute instead — but only once the
/// evidence is complete: a stored `_x` whose type the installed
/// `PropertyWrapperTypeResolving` recognizes as a property wrapper, and a
/// member variable `x`. A hand-written `_y` behind a computed `y` keeps
/// rendering: nothing says `_y`'s type wraps anything. dump is untouched; it
/// shows what the records say.
extension SwiftDeclarationPrinter {
    struct SynthesizedPropertyWrapperMembers: Sendable {
        /// Backing-storage field names (`_x`).
        var fieldNames: Set<String> = []
        /// Projection variable names (`$x`).
        var variableNames: Set<String> = []
        /// The wrapper attribute to print before each wrapped property, keyed
        /// by the property's name (`x`): the `.type`-wrapped wrapper type,
        /// with or without its generic arguments (see
        /// `wrapperAttributeTypeNode(fieldTypeNode:wrappedPropertyTypeNode:)`).
        var wrapperAttributeTypeNodesByVariableName: [String: Node] = [:]

        static var none: SynthesizedPropertyWrapperMembers { SynthesizedPropertyWrapperMembers() }

        func contains(_ member: OrderedMember) -> Bool {
            guard case .variable(let variable) = member else { return false }
            return variableNames.contains(variable.name)
        }

        /// The wrapper attribute `variable` was declared with, or `nil` when it
        /// is not a recognized wrapped property.
        func wrapperAttributeTypeNode(for variable: VariableDefinition) -> Node? {
            wrapperAttributeTypeNodesByVariableName[variable.name]
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
            guard let wrappedProperty = typeDefinition.variables.first(where: { $0.name == wrappedPropertyName }) else { continue }
            let fieldTypeNode = field.typeNode.materialize()
            guard let wrapperTypeNode = Self.nominalTypeNode(ofFieldType: fieldTypeNode),
                  propertyWrapperTypeResolver.isPropertyWrapperType(wrapperTypeNode)
            else { continue }
            synthesized.fieldNames.insert(field.name)
            synthesized.variableNames.insert("$" + wrappedPropertyName)
            synthesized.wrapperAttributeTypeNodesByVariableName[wrappedPropertyName] = Self.wrapperAttributeTypeNode(
                fieldTypeNode: fieldTypeNode,
                wrapperNominalTypeNode: wrapperTypeNode,
                wrappedPropertyTypeNode: Self.declaredTypeNode(of: wrappedProperty)
            )
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

    /// How the wrapper is spelled in the attribute. The binary records only
    /// the backing field's full type (`State<Int>`), never whether the source
    /// wrote the arguments; the rule mirrors what a reader would write: when
    /// the wrapper takes exactly one generic argument and that argument is
    /// the wrapped property's own type, the compiler infers it and the
    /// attribute is bare (`@State var x: Int`). Otherwise the arguments stay
    /// (`@Tagged<String, Int> var count: Int`), which is always valid source.
    static func wrapperAttributeTypeNode(fieldTypeNode: Node, wrapperNominalTypeNode: Node, wrappedPropertyTypeNode: Node?) -> Node {
        guard let boundGeneric = fieldTypeNode.firstChild,
              boundGeneric.kind == .boundGenericStructure || boundGeneric.kind == .boundGenericClass || boundGeneric.kind == .boundGenericEnum,
              let typeList = boundGeneric.children.first(where: { $0.kind == .typeList }),
              typeList.children.count == 1,
              let onlyArgument = typeList.firstChild,
              let wrappedPropertyTypeNode,
              onlyArgument == wrappedPropertyTypeNode
        else { return fieldTypeNode }
        return wrapperNominalTypeNode
    }

    /// The declared type of a member variable, read off its symbol node —
    /// the same descent `VariableNodePrinter._printRoot` performs: past the
    /// `global` wrapper (skipping an async / merged-function marker), past
    /// `static`, a `getter` / `setter`, a `methodDescriptor` or a
    /// `protocolWitness`, down to the `variable` node and its `type` child.
    /// `nil` when the node has no such shape.
    static func declaredTypeNode(of variable: VariableDefinition) -> Node? {
        var node = variable.node.materialize()
        for _ in 0 ..< 6 where node.kind != .variable {
            switch node.kind {
            case .global:
                guard let first = node.firstChild else { return nil }
                let skipsFirst = first.kind == .asyncFunctionPointer || first.kind == .asyncSuspendResumePartialFunction || first.kind == .mergedFunction
                guard let next = skipsFirst ? node.children.dropFirst().first : first else { return nil }
                node = next
            case .static, .getter, .setter, .methodDescriptor:
                guard let next = node.firstChild else { return nil }
                node = next
            case .protocolWitness:
                guard let next = node.children.dropFirst().first else { return nil }
                node = next
            default:
                return nil
            }
        }
        guard node.kind == .variable else { return nil }
        return node.children.first(where: { $0.kind == .type })
    }
}
