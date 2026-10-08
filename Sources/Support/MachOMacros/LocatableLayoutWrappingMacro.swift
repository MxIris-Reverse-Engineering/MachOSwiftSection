import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

// MARK: - LocatableLayoutWrappingMacro Definition

/// Generates the three storage-level requirements of `LocatableLayoutWrapper`
/// — `var layout: Layout`, `let offset: Int` and `init(layout:offset:)` —
/// which every wrapper spells out identically.
///
/// The conformance itself is deliberately NOT generated: the protocol name
/// stays on the declaration so the source remains searchable, and wrappers
/// carrying further conformances need not split their list between the
/// declaration and an expansion.
public struct LocatableLayoutWrappingMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDeclaration = declaration.as(StructDeclSyntax.self) else {
            context.diagnose(LocatableLayoutWrappingError.notAStruct.diag(at: Syntax(node)))
            return []
        }

        let accessLevel = accessLevelPrefix(of: structDeclaration.modifiers)
        let existingMembers = structDeclaration.memberBlock.members

        var generatedMembers: [DeclSyntax] = []

        if let conflicting = existingStoredProperty(named: "layout", in: existingMembers) {
            context.diagnose(LocatableLayoutWrappingError.memberAlreadyDeclared("layout").diag(at: Syntax(conflicting)))
        } else {
            generatedMembers.append("\(raw: accessLevel)var layout: Layout")
        }

        if let conflicting = existingStoredProperty(named: "offset", in: existingMembers) {
            context.diagnose(LocatableLayoutWrappingError.memberAlreadyDeclared("offset").diag(at: Syntax(conflicting)))
        } else {
            generatedMembers.append("\(raw: accessLevel)let offset: Int")
        }

        if let conflicting = existingLayoutOffsetInitializer(in: existingMembers) {
            context.diagnose(LocatableLayoutWrappingError.memberAlreadyDeclared("init(layout:offset:)").diag(at: Syntax(conflicting)))
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

// MARK: - Error Enum

enum LocatableLayoutWrappingError: CustomStringConvertible, Error, DiagnosticMessage {
    case notAStruct
    case memberAlreadyDeclared(String)

    var message: String {
        switch self {
        case .notAStruct:
            return "@LocatableLayoutWrapping can only be applied to structs."
        case .memberAlreadyDeclared(let name):
            return "@LocatableLayoutWrapping did not generate '\(name)' because the type declares it already."
        }
    }

    var description: String {
        return message
    }

    var diagnosticID: MessageID {
        switch self {
        case .notAStruct:
            return MessageID(domain: "LocatableLayoutWrappingMacro", id: "NotAStruct")
        case .memberAlreadyDeclared:
            return MessageID(domain: "LocatableLayoutWrappingMacro", id: "MemberAlreadyDeclared")
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
