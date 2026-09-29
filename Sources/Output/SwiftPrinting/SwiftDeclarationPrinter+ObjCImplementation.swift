import SwiftDeclaration
import SwiftDeclarationRendering
import Demangling
import Semantic
@_spi(Internals) import SwiftInspection

// The interface-side rendering of an `@objc @implementation` class's stored
// properties (evolution proposal `objc-implementation-class-recognition`).
// The header attribute itself is emitted by `printExtensionHeader`.

/// The field-offset comment of an `@objc @implementation` stored property:
/// the REAL offset from the ObjC ivar list, through the configured field
/// offset template when one is set — the same slot `FieldLayoutRenderer`
/// feeds for a Swift class's fields.
struct ObjCImplementationFieldOffsetComment: SemanticStringComponent {
    let instanceVariable: ObjCImplementationClassFacts.InstanceVariable
    let emit: Bool
    let transformer: FieldOffsetTransformer?

    package func buildComponents() -> [AtomicComponent] {
        guard emit else { return [] }
        if let transformer {
            return transformer((instanceVariable.offset, instanceVariable.offset + instanceVariable.size)).buildComponents()
        }
        return Comment("Field offset: 0x\(String(instanceVariable.offset, radix: 16))").buildComponents()
    }
}

extension SwiftDeclarationPrinter {
    /// A member built from accessor symbols that the ObjC ivar list shows to
    /// be STORED: rendered as `var name: Type` (no accessor block), the type
    /// taken from the field-offset symbol when it survived and from the
    /// accessor otherwise.
    @SemanticStringBuilder
    func printObjCImplementationStoredProperty(_ variable: VariableDefinition, storage: ObjCImplementationClassFacts.InstanceVariable, level: Int) async -> SemanticString {
        await dispatchingCatchedThrowing(.init(name: variable.name, kind: .variable)) {
            try await printThrowingObjCImplementationStoredProperty(variable, storage: storage, level: level)
        }
    }

    @SemanticStringBuilder
    func printThrowingObjCImplementationStoredProperty(_ variable: VariableDefinition, storage: ObjCImplementationClassFacts.InstanceVariable, level: Int) async throws -> SemanticString {
        let objcFacts = variable.resolvedObjCMemberFacts(trustingSelectorNameEvidence: trustsSelectorNameEvidence)
        for attribute in objcFacts.attributes {
            Keyword(attribute.keyword)
            // An `@objc(name)` the source spelled out (evolution proposal
            // `objc-member-selector-recovery`): the selector the ObjC method
            // table carries is not the one the compiler derives from the name.
            if attribute == .objc, let explicitSelector = objcFacts.explicitSelector {
                Standard("(\(explicitSelector))")
            }
            Space()
        }
        // A stored property with no setter symbol was declared `let`.
        Keyword(variable.hasSetter ? .var : .let)
        Space()
        MemberDeclaration(variable.name)
        Standard(":")
        Space()
        if let typeNode = storage.swiftTypeNode ?? Self.declaredTypeNode(ofVariableNode: variable.node) {
            try await printThrowingType(typeNode.materialize(), isProtocol: false, level: level)
        } else {
            InlineComment("type not recoverable")
        }
    }

    /// The `type` child of a `variable` node (context, identifier, type).
    static func declaredTypeNode(ofVariableNode node: NodeReference) -> NodeReference? {
        guard let last = node.children.last, last.kind == .type else { return nil }
        return last
    }

    /// The ivars no member definition accounts for — their accessor symbols
    /// were stripped, or they never had any. One with a field-offset symbol
    /// still renders as a declaration (the symbol carries name and type); one
    /// without renders as an honest comment naming what the binary does say
    /// (ObjC name, offset, size, encoding) rather than a fabricated type.
    @SemanticStringBuilder
    func renderUnrepresentedObjCImplementationInstanceVariables(_ extensionDefinition: ExtensionDefinition, level: Int) async -> SemanticString {
        let instanceVariables = extensionDefinition.unrepresentedObjCImplementationInstanceVariables
        if !instanceVariables.isEmpty {
            await MemberList(level: level) {
                for instanceVariable in instanceVariables {
                    await Rows(level: level) {
                        ObjCImplementationFieldOffsetComment(instanceVariable: instanceVariable, emit: configuration.printFieldOffset, transformer: configuration.fieldOffsetTransformer)
                        if let typeNode = instanceVariable.swiftTypeNode, let propertyName = instanceVariable.swiftPropertyName {
                            SemanticString {
                                Keyword(.var)
                                Space()
                                MemberDeclaration(propertyName)
                                Standard(":")
                                Space()
                            }
                            await printType(typeNode.materialize(), isProtocol: false, level: level)
                        } else {
                            Comment(Self.unrecoverableStoredPropertyComment(for: instanceVariable))
                        }
                    }
                }
            }
        }
    }

    static func unrecoverableStoredPropertyComment(for instanceVariable: ObjCImplementationClassFacts.InstanceVariable) -> String {
        let name = instanceVariable.name.isEmpty ? "<unnamed ivar>" : instanceVariable.name
        return "stored property \(name): Swift type not recoverable (ObjC ivar, offset 0x\(String(instanceVariable.offset, radix: 16)), size \(instanceVariable.size), encoding \"\(instanceVariable.typeEncoding)\")"
    }
}
