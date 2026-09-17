import SwiftDeclaration
import SwiftDeclarationRendering
@_spi(Internals) import Demangling
import Semantic

/// How the interface renders a definition's `wrappedProperties` — the
/// properties the source declared with a property wrapper, recovered at
/// index time (`TypeDefinition.wrappedProperties`). The interface reads like
/// the source, so the compiler-synthesized `_x` storage and `$x` projection
/// are left out and `x` carries the wrapper as its attribute; when `x`'s own
/// accessors are stripped, its declaration is printed in place of `_x`,
/// synthesized from the backing storage. dump is untouched; it shows what
/// the records say.
extension SwiftDeclarationPrinter {
    struct SynthesizedPropertyWrapperMembers: Sendable {
        /// Backing fields (`_x`) whose member variable `x` renders instead.
        var hiddenFieldNames: Set<String> = []
        /// Projections (`$x`), left out of the member list.
        var hiddenVariableNames: Set<String> = []
        /// The `@Wrapper` attribute of each declared member variable.
        var attributeTypeNodesByVariableName: [String: NodeReference] = [:]
        /// The wrapped properties whose declaration is synthesized, keyed by
        /// the backing field they render in place of.
        var synthesizedByBackingFieldName: [String: WrappedPropertyDefinition] = [:]

        static var none: SynthesizedPropertyWrapperMembers { SynthesizedPropertyWrapperMembers() }

        func contains(_ member: OrderedMember) -> Bool {
            guard case .variable(let variable) = member else { return false }
            return hiddenVariableNames.contains(variable.name)
        }

        /// The wrapper attribute `variable` was declared with, or `nil` when
        /// it is not a recognized wrapped property.
        func wrapperAttributeTypeNode(for variable: VariableDefinition) -> Node? {
            attributeTypeNodesByVariableName[variable.name]?.materialize()
        }

        /// The wrapped property rendered in place of `field`, when `field`
        /// is the backing storage of one whose accessors are stripped.
        func synthesizedDeclaration(inPlaceOfField field: FieldDefinition) -> WrappedPropertyDefinition? {
            synthesizedByBackingFieldName[field.name]
        }
    }

    /// The rendering view of `definition`'s wrapped properties; empty for
    /// anything but a type (an extension declares no stored properties).
    func synthesizedPropertyWrapperMembers(of definition: some Definition) -> SynthesizedPropertyWrapperMembers {
        guard let typeDefinition = definition as? TypeDefinition else { return .none }
        var members = SynthesizedPropertyWrapperMembers()
        for wrappedProperty in typeDefinition.wrappedProperties {
            members.hiddenVariableNames.insert(wrappedProperty.projectionName)
            switch wrappedProperty.origin {
            case .declaredMember:
                members.hiddenFieldNames.insert(wrappedProperty.backingFieldName)
                members.attributeTypeNodesByVariableName[wrappedProperty.name] = wrappedProperty.attributeTypeNode
            case .synthesized:
                members.synthesizedByBackingFieldName[wrappedProperty.backingFieldName] = wrappedProperty
            }
        }
        return members
    }

    /// `@Wrapper var x: T { get [set] }` for a wrapped property whose own
    /// accessors are stripped, built from the recovered declaration rather
    /// than from a symbol. Prints nothing for a declared-member origin.
    @SemanticStringBuilder
    func printThrowingSynthesizedWrappedProperty(_ wrappedProperty: WrappedPropertyDefinition, level: Int) async throws -> SemanticString {
        if case .synthesized(let declaredTypeNode, let hasSetter) = wrappedProperty.origin {
            Standard("@")
            try await printThrowingType(wrappedProperty.attributeTypeNode.materialize(), isProtocol: false, level: level)
            Space()
            // The variable node `VariableNodePrinter` reads: an identifier
            // and a type; the leading child only matters when it is an
            // `extension` or `protocol` context, which a stored property's
            // owner never is.
            let variableNode = Node.createTransient(kind: .variable, children: [
                Node.createTransient(kind: .identifier, contents: .text(wrappedProperty.name)),
                declaredTypeNode.materialize(),
            ])
            var printer = VariableNodePrinter(isStored: false, isOverride: false, hasSetter: hasSetter, indentation: level, delegate: self)
            try await printer.printRoot(variableNode)
        }
    }
}
