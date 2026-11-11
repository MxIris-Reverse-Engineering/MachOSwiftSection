@_spi(Internals) import Demangling
import Dependencies
import MachOSwiftSection
import SwiftInspection
@_spi(Internals) import MachOSymbols

/// `@Observable` expansion recovery, a step of `TypeDefinition.index(in:)`
/// (evolution proposal `observable-macro-folding`).
///
/// For a class `attachedMacros` marks `.observable`, it sorts the stored
/// `var`s into the storage of the properties the macro tracks and the ones
/// it left alone, and picks out the methods it generated — see
/// `ObservableMacroExpansion` and the rules in
/// `ObservableMacroExpansionRecovery`. Runs after wrapped-property recovery:
/// a wrapper's storage is not the macro's, and the macro cannot track a
/// wrapped property.
extension TypeDefinition {
    package func recoverObservableMacroExpansion(in machO: some MachOSwiftSectionRepresentableWithCache) {
        guard attachedMacros.contains(.observable) else {
            observableMacroExpansion = nil
            return
        }
        @Dependency(\.symbolIndexStore)
        var symbolIndexStore

        let storedProperties = fields.filter { !$0.flags.contains(.isArtificial) }
        // The names the evidence can be about: each storage `_x` and the
        // property `x` it would be, so a symbol of any other variable is
        // passed over before its context is compared.
        var candidateNames: Set<String> = []
        for storedProperty in storedProperties where storedProperty.name.hasPrefix("_") {
            candidateNames.insert(storedProperty.name)
            if let propertyName = ObservableMacroExpansionRecovery.trackedPropertyName(forBackingFieldName: storedProperty.name) {
                candidateNames.insert(propertyName)
            }
        }
        let typeContextNode = typeName.node.kind == .type ? typeName.node.children.first ?? typeName.node : typeName.node
        let evidence = ObservableMacroExpansionRecovery.SymbolEvidence(
            initAccessorNames: Self.variableNames(declaredBy: symbolIndexStore.symbols(of: .initAccessor, in: machO), in: typeContextNode, among: candidateNames),
            initialValueExpressionNames: {
                Self.variableNames(declaredBy: symbolIndexStore.symbols(of: .initializer, in: machO), in: typeContextNode, among: candidateNames)
            }
        )

        let recovered = ObservableMacroExpansionRecovery.recover(
            storedProperties: storedProperties.map { field in
                ObservableMacroExpansionRecovery.StoredProperty(
                    name: field.name,
                    typeNode: field.typeNode.materialize(),
                    isVariable: field.flags.contains(.isVariable),
                    hasAccessors: !field.accessors.isEmpty
                )
            },
            memberVariables: variables.filter { !$0.isGlobalOrStatic }.map { variable in
                ObservableMacroExpansionRecovery.MemberVariable(
                    name: variable.name,
                    declaredTypeNode: WrappedPropertyRecovery.declaredTypeNode(of: variable),
                    hasSetterOrModify: variable.hasSetter || variable.hasModifyAccessor
                )
            },
            claimedBackingFieldNames: Set(wrappedProperties.map(\.backingFieldName)),
            evidence: evidence
        )
        observableMacroExpansion = ObservableMacroExpansion(
            trackedProperties: recovered.trackedProperties,
            ignoredStoredPropertyNames: recovered.ignoredStoredPropertyNames,
            generatedFunctions: functions.filter { function in
                !function.isGlobalOrStatic
                    && ObservableMacroExpansionRecovery.isGeneratedFunction(
                        name: function.name,
                        argumentLabels: ObservableMacroExpansionRecovery.argumentLabels(ofFunction: function.node.materialize())
                    )
            }
        )
    }

    /// The names among `candidateNames` of the variables of the type
    /// `typeContextNode` names that `symbols` — init accessors or
    /// initial-value expressions — are for. Each symbol's own variable node
    /// is read: its first child is the declaring context, its second the
    /// name, wrapped in a `privateDeclName` for a private property.
    private static func variableNames(declaredBy symbols: [DemangledSymbol], in typeContextNode: NodeReference, among candidateNames: Set<String>) -> Set<String> {
        var names: Set<String> = []
        for symbol in symbols {
            guard let entityNode = symbol.demangledNode.children.first(where: { $0.kind == .initAccessor || $0.kind == .initializer }),
                  let variableNode = entityNode.children.first, variableNode.kind == .variable,
                  let nameNode = variableNode.children.dropFirst().first
            else { continue }
            let name: String?
            switch nameNode.kind {
            case .identifier:
                name = nameNode.text
            case .privateDeclName:
                name = nameNode.children.last(where: { $0.kind == .identifier })?.text
            default:
                name = nil
            }
            guard let name, candidateNames.contains(name),
                  let contextNode = variableNode.children.first, contextNode.structurallyEquals(typeContextNode)
            else { continue }
            names.insert(name)
        }
        return names
    }
}
