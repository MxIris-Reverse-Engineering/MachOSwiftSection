import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct AssociatedValueMacro: MemberMacro {
    
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            throw MacroError.requiresEnum
        }
        
        // Parse arguments, now handling the new enum-based access level.
        let (prefix, suffix, access) = try parseArguments(from: node, in: context)
        
        let accessModifier = determineAccessModifier(for: enumDecl, explicitAccess: access)
        
        let members = enumDecl.memberBlock.members
        let caseDecls = members.compactMap { $0.decl.as(EnumCaseDeclSyntax.self) }
        
        var newProperties: [DeclSyntax] = []
        
        for caseDecl in caseDecls {
            for element in caseDecl.elements {
                
                guard let parameterClause = element.parameterClause,
                      let firstParameter = parameterClause.parameters.first,
                      parameterClause.parameters.count == 1 else {
                    continue
                }
                
                let caseName = element.name
                let associatedValueType = firstParameter.type
                let bindingName = firstParameter.firstName ?? caseName
                
                let propertyName = makePropertyName(
                    for: caseName.text,
                    prefix: prefix,
                    suffix: suffix
                )
                
                let newProperty = try VariableDeclSyntax(
                    """
                    /// Returns the associated value of the `\(caseName)` case if `self` is `.\(caseName)`, otherwise returns `nil`.
                    \(raw: accessModifier)var \(raw: propertyName): \(associatedValueType)? {
                        switch self {
                        case .\(caseName)(let \(bindingName)):
                            return \(bindingName)
                        default:
                            return nil
                        }
                    }
                    """
                )
                
                newProperties.append(DeclSyntax(newProperty))
            }
        }
        
        return newProperties
    }
    
    /// Parses arguments from the attribute syntax.
    private static func parseArguments(from node: AttributeSyntax, in context: some MacroExpansionContext) throws -> (prefix: String?, suffix: String?, access: String?) {
        var prefix: String?
        var suffix: String?
        var access: String?
        
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return (nil, nil, nil)
        }
        
        for arg in arguments {
            // Handle labeled arguments: prefix and suffix
            if let label = arg.label?.text {
                guard let stringValue = arg.expression.as(StringLiteralExprSyntax.self)?.segments.first?.as(StringSegmentSyntax.self)?.content.text else {
                    // You might want to add a diagnostic here for invalid argument types.
                    continue
                }
                switch label {
                case "prefix":
                    prefix = stringValue
                case "suffix":
                    suffix = stringValue
                default:
                    // Unknown labeled argument
                    break
                }
            }
            // Handle unlabeled argument: access level
            else {
                // The expression should be a member access like `.public`
                guard let memberAccessExpr = arg.expression.as(MemberAccessExprSyntax.self)
//                      let base = memberAccessExpr.base, // The dot
//                      memberAccessExpr.declName.argumentNames == nil
                else { // Ensure it's a simple member, not a function call
                    throw MacroError.invalidAccessLevelArgument(node: arg.expression)
                }
                
                // The access level is the name of the member (e.g., "public")
                access = memberAccessExpr.declName.baseName.text
            }
        }
        
        return (prefix, suffix, access)
    }
    
    /// Determines the access modifier string for the generated properties.
    private static func determineAccessModifier(for enumDecl: EnumDeclSyntax, explicitAccess: String?) -> String {
        if let explicitAccess = explicitAccess, !explicitAccess.isEmpty {
            return explicitAccess + " "
        }

        for modifier in enumDecl.modifiers {
            let modifierText = modifier.name.text
            if ["public", "private", "fileprivate", "internal", "package"].contains(modifierText) {
                return modifierText + " "
            }
        }

        return ""
    }
    
    /// Constructs the final property name.
    private static func makePropertyName(for caseName: String, prefix: String?, suffix: String?) -> String {
        var finalName = caseName
        
        if let prefix = prefix, !prefix.isEmpty {
            finalName = prefix + caseName.capitalizedFirst()
        }
        
        if let suffix = suffix, !suffix.isEmpty {
            finalName += suffix
        }
        
        return finalName
    }
}

/// Helper to provide diagnostic messages.
private enum MacroError: Error, CustomStringConvertible, DiagnosticMessage {
    case requiresEnum
    case invalidAccessLevelArgument(node: ExprSyntax)
    
    var description: String {
        switch self {
        case .requiresEnum:
            return "@AssociatedValue can only be applied to an enum."
        case .invalidAccessLevelArgument:
            return "Invalid argument for access level. Please use a member of the `AccessLevel` enum, like `.public`."
        }
    }
    
    var message: String { description }
    
    var diagnosticID: MessageID {
        MessageID(domain: "\(AssociatedValueMacro.self)", id: "\(Self.self)")
    }
    
    var severity: DiagnosticSeverity { .error }
}

/// Helper to capitalize the first letter of a string.
extension String {
    fileprivate func capitalizedFirst() -> String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
