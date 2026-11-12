@_spi(Internals) import Demangling
import SwiftInspection

/// The rules of `@Observable` expansion recovery (evolution proposal
/// `observable-macro-folding`), kept free of any image so they can be
/// pinned on hand-built inputs. `TypeDefinition.recoverObservableMacroExpansion(in:)`
/// gathers the inputs from the image.
package enum ObservableMacroExpansionRecovery {
    /// A stored property, as its field record has it.
    package struct StoredProperty {
        package let name: String
        package let typeNode: Node
        /// Declared `var`: the macro tracks no `let`.
        package let isVariable: Bool
        /// Whether the property's own accessor symbols are in the image.
        package let hasAccessors: Bool

        package init(name: String, typeNode: Node, isVariable: Bool, hasAccessors: Bool = false) {
            self.name = name
            self.typeNode = typeNode
            self.isVariable = isVariable
            self.hasAccessors = hasAccessors
        }
    }

    /// An instance member variable with accessors in the image.
    package struct MemberVariable {
        package let name: String
        package let declaredTypeNode: Node?
        package let hasSetterOrModify: Bool

        package init(name: String, declaredTypeNode: Node?, hasSetterOrModify: Bool) {
            self.name = name
            self.declaredTypeNode = declaredTypeNode
            self.hasSetterOrModify = hasSetterOrModify
        }
    }

    /// What the symbol table says about the class's variables.
    package struct SymbolEvidence {
        /// The variables with an init accessor.
        package var initAccessorNames: Set<String>
        /// The variables with an initial-value expression — asked for once,
        /// and only when a storage's accessors leave it undecided: in an image
        /// that keeps its local symbols the expressions are many.
        package var initialValueExpressionNames: () -> Set<String>

        package init(initAccessorNames: Set<String> = [], initialValueExpressionNames: @escaping () -> Set<String> = { [] }) {
            self.initAccessorNames = initAccessorNames
            self.initialValueExpressionNames = initialValueExpressionNames
        }
    }

    /// The tracked properties and the stored `var`s the macro left alone,
    /// both in field order. `claimedBackingFieldNames` are the fields
    /// wrapped-property recovery recognized as a wrapper's storage: the
    /// macro cannot track a wrapped property, so the source declared it
    /// `@ObservationIgnored`.
    package static func recover(
        storedProperties: [StoredProperty],
        memberVariables: [MemberVariable],
        claimedBackingFieldNames: Set<String>,
        evidence: SymbolEvidence
    ) -> (trackedProperties: [ObservableMacroExpansion.TrackedProperty], ignoredStoredPropertyNames: [String]) {
        var trackedProperties: [ObservableMacroExpansion.TrackedProperty] = []
        var ignoredStoredPropertyNames: [String] = []
        var initialValueExpressionNames: Set<String>?
        for storedProperty in storedProperties where storedProperty.isVariable && storedProperty.name != ObservableMacroRecognition.registrarFieldName {
            guard !claimedBackingFieldNames.contains(storedProperty.name),
                  let propertyName = trackedPropertyName(forBackingFieldName: storedProperty.name)
            else {
                ignoredStoredPropertyNames.append(storedProperty.name)
                continue
            }
            let memberVariable = memberVariables.first { $0.name == propertyName }
            // A member `x` of another type is not what `_x` stores.
            if let declaredTypeNode = memberVariable?.declaredTypeNode, declaredTypeNode != InitAccessorFieldInference.referencedTypeNode(ofStoredType: storedProperty.typeNode) {
                ignoredStoredPropertyNames.append(storedProperty.name)
                continue
            }
            let trackingEvidence = trackingEvidence(
                propertyName: propertyName,
                storedProperty: storedProperty,
                memberVariable: memberVariable,
                initAccessorNames: evidence.initAccessorNames,
                initialValueExpressionNames: {
                    if let initialValueExpressionNames { return initialValueExpressionNames }
                    let names = evidence.initialValueExpressionNames()
                    initialValueExpressionNames = names
                    return names
                }
            )
            guard let trackingEvidence else {
                ignoredStoredPropertyNames.append(storedProperty.name)
                continue
            }
            trackedProperties.append(ObservableMacroExpansion.TrackedProperty(
                name: propertyName,
                backingFieldName: storedProperty.name,
                origin: memberVariable == nil ? .synthesized : .declaredMember,
                evidence: trackingEvidence
            ))
        }
        return (trackedProperties, ignoredStoredPropertyNames)
    }

    /// What tells `_x` apart from a stored property the source named so,
    /// strongest first, or `nil` when `_x` is one. An optimized, dead-stripped
    /// image — an OS framework — drops the init accessor and the accessors of
    /// every property nothing calls, local symbols kept or not, so absence
    /// alone never rules `_x` out: only a fact of `_x`'s own does.
    private static func trackingEvidence(
        propertyName: String,
        storedProperty: StoredProperty,
        memberVariable: MemberVariable?,
        initAccessorNames: Set<String>,
        initialValueExpressionNames: () -> Set<String>
    ) -> ObservableMacroExpansion.TrackedProperty.Evidence? {
        if initAccessorNames.contains(propertyName) {
            return .initAccessor
        }
        if memberVariable?.hasSetterOrModify == true {
            return .accessors
        }
        // The initial value belongs to whichever property the source wrote it
        // on: `x` when the macro moved the storage, `_x` when it is its own.
        let initialValueExpressionNames = initialValueExpressionNames()
        if initialValueExpressionNames.contains(storedProperty.name) {
            return nil
        }
        if initialValueExpressionNames.contains(propertyName) {
            return .initialValueExpression
        }
        // The image keeps `_x`'s accessors and none of `x`'s: the macro's
        // storage and its computed property go together, kept by the same
        // vtable or dropped by the same strip.
        if storedProperty.hasAccessors, memberVariable == nil {
            return nil
        }
        return .backingFieldName
    }

    /// `x` for the storage `_x` the macro generates; `nil` for a name that
    /// cannot be one — no leading underscore, nothing after it, or a `$`
    /// after it, which only compiler- and macro-generated names start with.
    package static func trackedPropertyName(forBackingFieldName backingFieldName: String) -> String? {
        guard backingFieldName.hasPrefix("_") else { return nil }
        let propertyName = backingFieldName.dropFirst()
        guard let firstCharacter = propertyName.first, firstCharacter != "$" else { return nil }
        return String(propertyName)
    }

    /// Whether a method of the class is one the macro generates, by its base
    /// name and argument labels: `access(keyPath:)`,
    /// `withMutation(keyPath:_:)` or `shouldNotifyObservers(_:_:)`. The macro
    /// adds none the class declares itself, so one written in the source
    /// stands in for the generated one.
    package static func isGeneratedFunction(name: String, argumentLabels: [String]) -> Bool {
        switch name {
        case "access":
            return argumentLabels == ["keyPath"]
        case "withMutation":
            return argumentLabels == ["keyPath", "_"]
        case "shouldNotifyObservers":
            // The demangler leaves out the label list of a function whose
            // arguments are all unlabeled.
            return argumentLabels.isEmpty || argumentLabels == ["_", "_"]
        default:
            return false
        }
    }

    /// The argument labels of a function's own declaration, `_` for an
    /// unlabeled argument — read from the declaration node's direct
    /// children, never by searching the tree, whose context comes first
    /// (`local-type-context-names`). Empty when the node is not a function or
    /// has no label list.
    package static func argumentLabels(ofFunction node: Node) -> [String] {
        guard let declarationNode = functionDeclarationNode(of: node),
              let labelList = declarationNode.children.first(where: { $0.kind == .labelList })
        else { return [] }
        return labelList.children.map { label in
            label.kind == .firstElementMarker ? "_" : label.text ?? "_"
        }
    }

    /// The `function` node a member function's symbol declares — past the
    /// `global` wrapper (skipping an async or merged-function marker), past
    /// `static` or a `methodDescriptor`, and past a `protocolWitness`'s
    /// conformance.
    private static func functionDeclarationNode(of node: Node) -> Node? {
        var node = node
        for _ in 0 ..< 6 where node.kind != .function {
            switch node.kind {
            case .global:
                guard let first = node.firstChild else { return nil }
                let skipsFirst = first.kind == .asyncFunctionPointer || first.kind == .asyncSuspendResumePartialFunction || first.kind == .mergedFunction
                guard let next = skipsFirst ? node.children.dropFirst().first : first else { return nil }
                node = next
            case .static, .methodDescriptor:
                guard let next = node.firstChild else { return nil }
                node = next
            case .protocolWitness:
                guard let next = node.children.dropFirst().first else { return nil }
                node = next
            default:
                return nil
            }
        }
        return node.kind == .function ? node : nil
    }
}
