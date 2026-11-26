import SwiftDeclaration
import SwiftDeclarationRendering
import Demangling
import Semantic
@_spi(Internals) import SwiftInspection
import SwiftObjCInterop

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
    let marksStructure: Bool

    package func buildComponents() -> [AtomicComponent] {
        guard emit else { return [] }
        if let transformer {
            let output = transformer((instanceVariable.offset, instanceVariable.offset + instanceVariable.size))
            return StructuredComment.printedTemplate(output, markingStructure: marksStructure, as: .fieldOffset).components
        }
        return StructuredComment.fieldOffset(instanceVariable.offset).atoms(markingStructure: marksStructure, as: .fieldOffset)
    }
}

extension SwiftDeclarationPrinter {
    /// A member built from accessor symbols that the ObjC ivar list shows to
    /// be STORED: rendered as `var name: Type` (no accessor block), the type
    /// taken from the field-offset symbol when it survived and from the
    /// accessor otherwise. `objcProperty` is the Objective-C property it is
    /// exposed as, if any: it makes the property `var` when the class offers
    /// Objective-C a setter whose Swift symbol `-O` inlined away, and `weak`
    /// when it is one (evolution proposal `swift-first-imported-declarations`).
    @SemanticStringBuilder
    func printObjCImplementationStoredProperty(_ variable: VariableDefinition, storage: ObjCImplementationClassFacts.InstanceVariable, objcProperty: ObjCImplementationClassFacts.Property?, level: Int) async -> SemanticString {
        await dispatchingCatchedThrowing(.init(name: variable.name, kind: .variable)) {
            try await printThrowingObjCImplementationStoredProperty(variable, storage: storage, objcProperty: objcProperty, level: level)
        }
    }

    @SemanticStringBuilder
    func printThrowingObjCImplementationStoredProperty(_ variable: VariableDefinition, storage: ObjCImplementationClassFacts.InstanceVariable, objcProperty: ObjCImplementationClassFacts.Property?, level: Int) async throws -> SemanticString {
        try await printUnderObjCVerdicts(of: variable.resolvedObjCMemberFacts(trustingSelectorNameEvidence:)) { objcFacts in
            objcAttributes(objcFacts)
            let isLazy = storage.lazyPropertyName != nil
            if isLazy {
                Keyword(.lazy)
                Space()
                Keyword(.var)
            } else if objcProperty?.isWeak == true {
                // A `weak` property is a `var`, settable or not.
                Keyword(.weak)
                Space()
                Keyword(.var)
            } else {
                // A stored property with no setter symbol and no Objective-C
                // setter was declared `let`.
                let isSettable = variable.hasSetter || objcProperty.map { !$0.isReadOnly } == true
                Keyword(isSettable ? .var : .let)
            }
            Space()
            MemberDeclaration(variable.name)
            Standard(":")
            Space()
            // A `lazy var` renders as a Swift type's own lazy field does: the
            // getter's caller-facing type, not its storage's `Optional`.
            let declaredTypeNode = WrappedPropertyRecovery.declaredTypeNode(of: variable)
            let typeNode = isLazy
                ? declaredTypeNode ?? storage.swiftTypeNode?.materialize()
                : storage.swiftTypeNode?.materialize() ?? declaredTypeNode
            if let typeNode {
                try await printThrowingType(typeNode, isProtocol: false, level: level)
            } else {
                comment(.inlineNote("type not recoverable"), as: .note)
            }
        }
    }

    /// The ivars no member definition accounts for — their accessor symbols
    /// were stripped, or they never had any. One with a field-offset symbol
    /// still renders as a declaration (the symbol carries name and type); one
    /// without renders as an honest comment naming what the binary does say
    /// (ObjC name, offset, size, encoding) rather than a fabricated type.
    ///
    /// Before falling back to the comment, the Objective-C side is asked for
    /// the Swift type: a complete ivar encoding is the Swift type itself, and
    /// a `?` one the bridged form of the Objective-C property synthesized on
    /// the ivar (`ObjCInstanceVariableSwiftType`, evolution proposal
    /// `objc-ivar-type-recovery`).
    ///
    /// `standIns` replace that comment with a declaration the Objective-C side
    /// gives, keyed by the ivar's identity: the Generated Interface prints the
    /// Objective-C property synthesized on the ivar as Swift imports it,
    /// whose type is the one Objective-C sees (evolution proposal
    /// `swift-first-imported-declarations`). The Swift interface passes none —
    /// that type is not the Swift property's.
    @SemanticStringBuilder
    func renderUnrepresentedObjCImplementationInstanceVariables(_ extensionDefinition: ExtensionDefinition, level: Int, standIns: [ObjectIdentifier: ObjCImportedMemberDefinition] = [:]) async -> SemanticString {
        let instanceVariables = extensionDefinition.unrepresentedObjCImplementationInstanceVariables
        if !instanceVariables.isEmpty {
            await MemberList(level: level) {
                for instanceVariable in instanceVariables {
                    await Rows(level: level) {
                        optionalContent(.printFieldOffset) {
                            ObjCImplementationFieldOffsetComment(instanceVariable: instanceVariable, emit: true, transformer: configuration.fieldOffsetTransformer, marksStructure: marksCommentStructure)
                        }
                        if let standIn = standIns[ObjectIdentifier(instanceVariable)] {
                            await printObjCImportedMember(standIn, level: level)
                        } else if let typeNode = instanceVariable.swiftTypeNode, let propertyName = instanceVariable.swiftPropertyName {
                            SemanticString {
                                // With no getter joined, a `lazy var`'s storage
                                // type is the honest fallback, as for a Swift
                                // type's own lazy field.
                                if let lazyPropertyName = instanceVariable.lazyPropertyName {
                                    Keyword(.lazy)
                                    Space()
                                    Keyword(.var)
                                    Space()
                                    MemberDeclaration(lazyPropertyName)
                                } else {
                                    Keyword(.var)
                                    Space()
                                    MemberDeclaration(propertyName)
                                }
                                Standard(":")
                                Space()
                            }
                            await printType(typeNode.materialize(), isProtocol: false, level: level)
                        } else if let recoveredType = recoveredSwiftType(of: instanceVariable, in: extensionDefinition) {
                            // One row: `Rows` puts each component on a line of its own.
                            await recoveredStoredPropertyDeclaration(named: instanceVariable.name, type: recoveredType, level: level)
                        } else {
                            comment(.note(Self.unrecoverableStoredPropertyComment(for: instanceVariable)), as: .note)
                        }
                    }
                }
            }
        }
    }

    /// The Swift type the Objective-C side gives `instanceVariable`, or `nil`
    /// when it gives none. An unnamed ivar names no property to declare.
    private func recoveredSwiftType(of instanceVariable: ObjCImplementationClassFacts.InstanceVariable, in extensionDefinition: ExtensionDefinition) -> ObjCInstanceVariableSwiftType? {
        guard !instanceVariable.name.isEmpty, let facts = extensionDefinition.objcImplementation else { return nil }
        let objcProperty = facts.objcProperty(storedIn: instanceVariable, swiftPropertyName: instanceVariable.swiftPropertyName ?? instanceVariable.name)
        return ObjCInstanceVariableSwiftType(instanceVariable: instanceVariable, objcProperty: objcProperty, in: machO)
    }

    /// `[weak] var|let name: Type` for a stored property whose type the
    /// Objective-C side gave. With an Objective-C property, `readonly` makes
    /// it a `let`; with none, nothing says it cannot be set.
    @SemanticStringBuilder
    private func recoveredStoredPropertyDeclaration(named name: String, type recoveredType: ObjCInstanceVariableSwiftType, level: Int) async -> SemanticString {
        if recoveredType.isWeak {
            Keyword(.weak)
            Space()
            Keyword(.var)
        } else {
            Keyword(recoveredType.isReadOnly ? .let : .var)
        }
        Space()
        MemberDeclaration(name)
        Standard(":")
        Space()
        await printType(recoveredType.typeNode, isProtocol: false, level: level)
    }

    static func unrecoverableStoredPropertyComment(for instanceVariable: ObjCImplementationClassFacts.InstanceVariable) -> String {
        let name = instanceVariable.name.isEmpty ? "<unnamed ivar>" : instanceVariable.name
        return "stored property \(name): Swift type not recoverable (ObjC ivar, offset 0x\(String(instanceVariable.offset, radix: 16)), size \(instanceVariable.size), encoding \"\(instanceVariable.typeEncoding)\")"
    }
}
