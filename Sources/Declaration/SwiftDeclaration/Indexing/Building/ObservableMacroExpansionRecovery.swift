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

        package init(name: String, typeNode: Node, isVariable: Bool) {
            self.name = name
            self.typeNode = typeNode
            self.isVariable = isVariable
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
        package var initAccessorNames: Set<String> = []
        /// The variables with an initial-value expression. Gathered only
        /// when the image keeps no local symbol: only then do the expressions
        /// still standing decide anything.
        package var initialValueExpressionNames: Set<String> = []
        /// Whether the image carries any local Swift symbol. When it does, a
        /// tracked property's init accessor is among them, so its absence
        /// says `_x` is a stored property of its own; when it does not,
        /// absence says nothing.
        package var imageHasLocalSwiftSymbols: Bool = true

        package init(initAccessorNames: Set<String> = [], initialValueExpressionNames: Set<String> = [], imageHasLocalSwiftSymbols: Bool = true) {
            self.initAccessorNames = initAccessorNames
            self.initialValueExpressionNames = initialValueExpressionNames
            self.imageHasLocalSwiftSymbols = imageHasLocalSwiftSymbols
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
        for storedProperty in storedProperties where storedProperty.isVariable && storedProperty.name != ObservableMacroRecognition.registrarFieldName {
            guard !claimedBackingFieldNames.contains(storedProperty.name),
                  let propertyName = trackedPropertyName(forBackingFieldName: storedProperty.name)
            else {
                ignoredStoredPropertyNames.append(storedProperty.name)
                continue
            }
            let memberVariable = memberVariables.first { $0.name == propertyName }
            // A member `x` of another type is not what `_x` stores.
            if let declaredTypeNode = memberVariable?.declaredTypeNode, declaredTypeNode != referencedTypeNode(ofStoredType: storedProperty.typeNode) {
                ignoredStoredPropertyNames.append(storedProperty.name)
                continue
            }
            guard let evidence = trackingEvidence(propertyName: propertyName, backingFieldName: storedProperty.name, memberVariable: memberVariable, evidence: evidence) else {
                ignoredStoredPropertyNames.append(storedProperty.name)
                continue
            }
            trackedProperties.append(ObservableMacroExpansion.TrackedProperty(
                name: propertyName,
                backingFieldName: storedProperty.name,
                origin: memberVariable == nil ? .synthesized : .declaredMember,
                evidence: evidence
            ))
        }
        return (trackedProperties, ignoredStoredPropertyNames)
    }

    private static func trackingEvidence(
        propertyName: String,
        backingFieldName: String,
        memberVariable: MemberVariable?,
        evidence: SymbolEvidence
    ) -> ObservableMacroExpansion.TrackedProperty.Evidence? {
        if evidence.initAccessorNames.contains(propertyName) {
            return .initAccessor
        }
        // An image with local symbols keeps every tracked property's init
        // accessor, so a `_x` without one is a stored property of its own.
        guard !evidence.imageHasLocalSwiftSymbols else { return nil }
        if memberVariable?.hasSetterOrModify == true {
            return .accessors
        }
        // The initial value belongs to whichever property the source wrote it
        // on: `x` when the macro moved the storage, `_x` when it is its own.
        if evidence.initialValueExpressionNames.contains(backingFieldName) {
            return nil
        }
        if evidence.initialValueExpressionNames.contains(propertyName) {
            return .initialValueExpression
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

    /// The type a stored property's accessors traffic in: its field type
    /// without the `weak` / `unowned` / `unowned(unsafe)` storage around it,
    /// with the `type` node around it — the shape a member variable's
    /// declared type has.
    package static func referencedTypeNode(ofStoredType storedTypeNode: Node) -> Node {
        var node = storedTypeNode
        while node.kind == .type, let referenceStorage = node.firstChild,
              referenceStorage.kind == .weak || referenceStorage.kind == .unowned || referenceStorage.kind == .unmanaged,
              let referencedTypeNode = referenceStorage.firstChild {
            node = referencedTypeNode
        }
        return node
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
