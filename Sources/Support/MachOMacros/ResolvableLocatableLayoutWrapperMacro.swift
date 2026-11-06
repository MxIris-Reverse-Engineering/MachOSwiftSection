import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - ResolvableLocatableLayoutWrapperMacro Definition

/// Makes a wrapper struct a `ResolvableLocatableLayoutWrapper`.
///
/// The member role generates the three storage-level requirements of
/// `LocatableLayoutWrapper` — `var layout: Layout`, `let offset: Int` and
/// `init(layout:offset:)` — which every wrapper spells out identically.
///
/// The extension role names every protocol of the hierarchy —
/// `LocatableLayoutWrapper`, `Resolvable` and the ones they refine — except
/// those the declaration itself spells out. See the extension role for why it
/// does not trust the compiler's list of missing protocols.
public struct ResolvableLocatableLayoutWrapperMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(ResolvableLocatableLayoutWrapperError.notAStruct.diag(at: Syntax(node)))
            return []
        }

        let accessLevel = accessLevelPrefix(of: structDeclaration.modifiers)
        let existingMembers = structDeclaration.memberBlock.members

        var generatedMembers: [DeclSyntax] = []

        if let conflicting = existingStoredProperty(named: "layout", in: existingMembers) {
            context.diagnose(ResolvableLocatableLayoutWrapperError.memberAlreadyDeclared("layout").diag(at: Syntax(conflicting)))
        } else {
            generatedMembers.append("\(raw: accessLevel)var layout: Layout")
        }

        if let conflicting = existingStoredProperty(named: "offset", in: existingMembers) {
            context.diagnose(ResolvableLocatableLayoutWrapperError.memberAlreadyDeclared("offset").diag(at: Syntax(conflicting)))
        } else {
            generatedMembers.append("\(raw: accessLevel)let offset: Int")
        }

        if let conflicting = existingLayoutOffsetInitializer(in: existingMembers) {
            context.diagnose(ResolvableLocatableLayoutWrapperError.memberAlreadyDeclared("init(layout:offset:)").diag(at: Syntax(conflicting)))
        } else {
            generatedMembers.append(
                """
                \(raw: accessLevel)init(layout: Layout, offset: Int) {
                    self.layout = layout
                    self.offset = offset
                }
                """
            )
        }

        return generatedMembers
    }

    // MARK: - Helper Functions

    /// The host's own access level, rendered as a modifier prefix (`"public "`)
    /// so the generated members are exactly as visible as the type carrying
    /// them. Returns an empty string when the host is implicitly internal.
    private static func accessLevelPrefix(of modifiers: DeclModifierListSyntax) -> String {
        for modifier in modifiers {
            switch modifier.name.tokenKind {
            case .keyword(.public), .keyword(.package), .keyword(.internal),
                 .keyword(.fileprivate), .keyword(.private):
                return "\(modifier.name.text) "
            default:
                continue
            }
        }
        return ""
    }

    private static func existingStoredProperty(
        named name: String,
        in members: MemberBlockItemListSyntax
    ) -> VariableDeclSyntax? {
        for member in members {
            guard let variableDeclaration = member.decl.as(VariableDeclSyntax.self) else { continue }
            let declaresName = variableDeclaration.bindings.contains { binding in
                binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == name
            }
            if declaresName { return variableDeclaration }
        }
        return nil
    }

    private static func existingLayoutOffsetInitializer(
        in members: MemberBlockItemListSyntax
    ) -> InitializerDeclSyntax? {
        for member in members {
            guard let initializerDeclaration = member.decl.as(InitializerDeclSyntax.self) else { continue }
            let argumentLabels = initializerDeclaration.signature.parameterClause.parameters.map(\.firstName.text)
            if argumentLabels == ["layout", "offset"] { return initializerDeclaration }
        }
        return nil
    }
}

// MARK: - Extension Role

extension ResolvableLocatableLayoutWrapperMacro: ExtensionMacro {
    /// The protocols the macro declaration lists in `conformances:`, in the
    /// same order. Keep the two lists identical.
    static let conformanceHierarchy = [
        "LocatableLayoutWrapper",
        "Resolvable",
        "LayoutWrapper",
        "Equatable",
        "Sendable",
    ]

    /// Names every protocol of the hierarchy the declaration does not spell
    /// out itself, whatever `protocols` says.
    ///
    /// Before expanding, the compiler records each listed protocol as a
    /// placeholder conformance. Two consequences make its list of missing
    /// protocols unreliable (Swift 6.3):
    /// - A protocol implied by a placeholder (`LayoutWrapper` through
    ///   `LocatableLayoutWrapper`) counts as present, so it is left out of
    ///   `protocols`; and the conformance implied by the expanded extension can
    ///   lose to the one implied by the placeholder, which has no conformance
    ///   behind it. `TypeMetadataRecord.layoutSize` failed with "requires that
    ///   'TypeMetadataRecord' conform to 'LayoutWrapper'" in one file and
    ///   compiled in the next.
    /// - A placeholder blocks the conformance a refining protocol implies
    ///   (`EnumDescriptor` is a `LayoutWrapper` through
    ///   `TypeContextDescriptorProtocol`), so a protocol left out of the
    ///   expansion ends with no conformance at all.
    ///
    /// Naming each one explicitly gives every placeholder a real conformance
    /// to give way to. A conformance a refining protocol already implies is
    /// superseded by the explicit one without a diagnostic.
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // The member role reports a non-struct host; reporting it again here
        // would only duplicate the error.
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else { return [] }

        let declaredInheritedTypeNames = Set(
            structDeclaration.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription) ?? []
        )
        let conformances = conformanceHierarchy.filter { !declaredInheritedTypeNames.contains($0) }
        guard !conformances.isEmpty else { return [] }

        let conformanceList = conformances.joined(separator: ", ")
        let extensionDeclaration: DeclSyntax = "extension \(type.trimmed): \(raw: conformanceList) {}"
        return [extensionDeclaration.cast(ExtensionDeclSyntax.self)]
    }
}

// MARK: - Error Enum

enum ResolvableLocatableLayoutWrapperError: CustomStringConvertible, Error, DiagnosticMessage {
    case notAStruct
    case memberAlreadyDeclared(String)

    var message: String {
        switch self {
        case .notAStruct:
            return "@ResolvableLocatableLayoutWrapper can only be applied to structs."
        case .memberAlreadyDeclared(let name):
            return "@ResolvableLocatableLayoutWrapper did not generate '\(name)' because the type declares it already."
        }
    }

    var description: String {
        return message
    }

    var diagnosticID: MessageID {
        switch self {
        case .notAStruct:
            return MessageID(domain: "ResolvableLocatableLayoutWrapperMacro", id: "NotAStruct")
        case .memberAlreadyDeclared:
            return MessageID(domain: "ResolvableLocatableLayoutWrapperMacro", id: "MemberAlreadyDeclared")
        }
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .notAStruct: return .error
        case .memberAlreadyDeclared: return .warning
        }
    }

    func diag(at node: Syntax) -> SwiftDiagnostics.Diagnostic {
        return SwiftDiagnostics.Diagnostic(node: node, message: self)
    }
}
