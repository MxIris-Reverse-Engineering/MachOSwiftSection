import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct CaseCheckableMacro: MemberMacro {
    // Use the non-deprecated expansion method.
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // 1. Validate that the macro is attached to an enum.
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw CaseCheckableMacroError.requiresEnum
        }

        // 2. Determine the access level from the macro's arguments.
        // Default to 'internal' if no argument is provided.
        let accessLevel = node.arguments?
            .as(LabeledExprListSyntax.self)?
            .first?.expression
            .as(MemberAccessExprSyntax.self)?
            .declName.baseName.text ?? ""

        // 3. Find all case elements within the enum.
        let caseElements = enumDecl.memberBlock.members.flatMap { member -> [EnumCaseElementSyntax] in
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else {
                return []
            }
            return Array(caseDecl.elements)
        }

        // 4. Generate a computed property for each case element.
        return caseElements.map { element in
            // The token for the case name, e.g., `loading` or `` `extension` ``.
            // This is used directly in the `case` pattern to handle keywords correctly.
            let caseNameForPattern = element.name

            // To create a valid property name, we need the raw text without backticks.
            var cleanNameText = caseNameForPattern.text
            if cleanNameText.hasPrefix("`") && cleanNameText.hasSuffix("`") {
                cleanNameText = String(cleanNameText.dropFirst().dropLast())
            }

            // Create the property name, e.g., 'extension' -> 'isExtension'
            let propertyNameIdentifier: TokenSyntax
            if let firstCharacter = cleanNameText.first {
                let propertyNameString = "is" + firstCharacter.uppercased() + String(cleanNameText.dropFirst())
                propertyNameIdentifier = .identifier(propertyNameString)
            } else {
                // This is a fallback for an empty case name, which is syntactically impossible
                // but good to handle defensively.
                propertyNameIdentifier = .identifier("is" + cleanNameText)
            }

            // Generate the code for the computed property.
            let decl: DeclSyntax =
                """
                \(raw: accessLevel) var \(propertyNameIdentifier): Bool {
                    switch self {
                    case .\(caseNameForPattern):
                        return true
                    default:
                        return false
                    }
                }
                """

            return decl
        }
    }
}

/// Error type for the IsCase macro.
/// Conforms to DiagnosticMessage to provide rich, build-integrated error messages.
private enum CaseCheckableMacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case requiresEnum

    var description: String {
        switch self {
        case .requiresEnum:
            return "@IsCase can only be applied to an enum."
        }
    }

    var message: String {
        return description
    }

    var diagnosticID: MessageID {
        // The domain should be the name of your macro implementation type.
        // The id can be the name of the error case.
        MessageID(domain: "CaseCheckableMacro", id: "\(self)")
    }

    var severity: DiagnosticSeverity {
        return .error
    }
}
