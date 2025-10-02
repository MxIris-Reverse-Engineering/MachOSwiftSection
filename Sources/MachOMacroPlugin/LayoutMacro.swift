import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

// MARK: - LayoutMacro Definition

public struct LayoutMacro: PeerMacro, MemberMacro, ExtensionMacro {
    // MARK: - MemberMacro

    // Adds `func layoutOffset(of field: ProtocolNameField) -> Int`
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            let errorNode = Syntax(node)
            context.diagnose(LayoutError.notAProtocol.diag(at: errorNode))
            return []
        }

        let protocolName = protocolDecl.name.text
        let fieldEnumName = "\(protocolName)Field"

        let hasLayoutOffsetFunc = protocolDecl.memberBlock.members.contains { member in
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                return funcDecl.name.text == "layoutOffset" &&
                    funcDecl.signature.parameterClause.parameters.count == 1 &&
                    funcDecl.signature.parameterClause.parameters.first?.firstName.text == "of" &&
                    funcDecl.signature.parameterClause.parameters.first?.secondName?.text == "field" &&
                    funcDecl.signature.parameterClause.parameters.first?.type.trimmedDescription == fieldEnumName &&
                    funcDecl.signature.returnClause?.type.trimmedDescription == "Int"
            }
            return false
        }

        if !hasLayoutOffsetFunc {
            return [
                "func offset(of field: \(raw: fieldEnumName)) -> Int",
                "static func offset(of field: \(raw: fieldEnumName)) -> Int",
            ]
        }
        return []
    }

    // MARK: - PeerMacro

    // Generates `enum ProtocolNameField` and `extension ProtocolName`
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            let errorNode = Syntax(node)
            context.diagnose(LayoutError.notAProtocol.diag(at: errorNode))
            return []
        }

        let protocolName = protocolDecl.name.text
        let fieldEnumName = "\(protocolName)Field"

        // Collect only direct fields of the current protocol
        var directFields: [Field] = []
        for member in protocolDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self),
               varDecl.bindingSpecifier.tokenKind == .keyword(.var) {
                for binding in varDecl.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                       let typeAnnotation = binding.typeAnnotation {
                        directFields.append(Field(name: identifier.identifier.text, type: typeAnnotation.type))
                    }
                }
            }
        }
        let isDirectFieldsEmpty = directFields.isEmpty
        // 1. Generate the ProtocolNameField enum
        var enumCases: [String] = []
        for field in directFields {
            enumCases.append("case \(field.name)")
        }

        if isDirectFieldsEmpty {
            enumCases.append("case __empty")
        }
        
        // Determine the starting offset. If inheriting, use parent's size.
        var baseOffsetInitialization = "var currentOffset = 0"
        if let inheritanceClause = protocolDecl.inheritanceClause {
            // We need to find the *first* @Layout parent to get its size.
            // This still requires same-file lookup for the parent to check if it's @Layout.
            // If we can't find it or it's not @Layout, we assume 0.
            // This is a simplification. A robust solution would need more info or conventions.
            // For now, let's assume the first inherited type *is* the @Layout parent if one exists.
            // This is a strong assumption.
            if let lastInheritedType = inheritanceClause.inheritedTypes.last?.type,
               let inheritedProtocolName = lastInheritedType.as(IdentifierTypeSyntax.self)?.name.text, inheritedProtocolName != "LayoutProtocol" {
                // Check if this parent is also @Layout (requires same-file lookup for the attribute)
                // For simplicity of this example, we'll just assume it is if it's named.
                // A more robust check would use findProtocolDeclarationSyntax.
                // However, the request was to *not* look up members, but we might need to look up the parent's Field enum.
                let parentFieldEnumName = "\(inheritedProtocolName)Field"
                baseOffsetInitialization = "var currentOffset = \(parentFieldEnumName)._cachedOffsets.endOffset"
            }
        }

        var calculationLogicLines: [String] = []
        calculationLogicLines.append(baseOffsetInitialization) // Start with parent's size or 0
        calculationLogicLines.append("var offsets = [\(fieldEnumName): Int]()")

        for field in directFields {
            let typeString = field.type.trimmedDescription
            // Offsets for direct fields are relative to currentOffset (which starts after parent)
            calculationLogicLines.append("offsets[.\(field.name)] = currentOffset")
            calculationLogicLines.append("currentOffset += MemoryLayout<\(typeString)>.size")
        }
        // The final currentOffset is the total size *including* the parent's size contribution
        // and this protocol's direct fields.
        // However, the 'size' stored in this enum should be the size of *this protocol's direct fields only*
        // if we follow the pattern strictly.
        // Let's adjust: size should be (currentOffset - initialOffset)
        calculationLogicLines.append("return (offsets, currentOffset)")

        let calculationBlock = calculationLogicLines.joined(separator: "\n            ")

        let enumDeclSyntax: DeclSyntax =
            """
            public enum \(raw: fieldEnumName) {
                \(raw: enumCases.joined(separator: "\n    "))

                // Static cache for this protocol's direct fields
                static let _cachedOffsets: (cache: [\(raw: fieldEnumName): Int], endOffset: Int) = {
                    \(raw: calculationBlock)
                }()
            }
            """

        // 2. Generate the extension with layoutOffset implementation

        return [enumDeclSyntax]
    }

    // MARK: - Extension Macro

    public static func expansion(of node: SwiftSyntax.AttributeSyntax, attachedTo declaration: some SwiftSyntax.DeclGroupSyntax, providingExtensionsOf type: some SwiftSyntax.TypeSyntaxProtocol, conformingTo protocols: [SwiftSyntax.TypeSyntax], in context: some SwiftSyntaxMacros.MacroExpansionContext) throws -> [SwiftSyntax.ExtensionDeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            let errorNode = Syntax(node)
            context.diagnose(LayoutError.notAProtocol.diag(at: errorNode))
            return []
        }

        let protocolName = protocolDecl.name.text
        let fieldEnumName = "\(protocolName)Field"
        var directFields: [Field] = []
        for member in protocolDecl.memberBlock.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self),
               varDecl.bindingSpecifier.tokenKind == .keyword(.var) {
                for binding in varDecl.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                       let typeAnnotation = binding.typeAnnotation {
                        directFields.append(Field(name: identifier.identifier.text, type: typeAnnotation.type))
                    }
                }
            }
        }
        let extensionDeclSyntax: ExtensionDeclSyntax = try .init(
            """
            extension \(raw: protocolName) {
                public func offset(of field: \(raw: fieldEnumName)) -> Int {
                    // The offsets in `fieldEnumName._cachedOffsets.cache` are already absolute
                    // from the perspective of where this protocol's fields start.
                    guard let relativeOffset = \(raw: fieldEnumName)._cachedOffsets.cache[field] else {
                        fatalError("Offset for field \\(field) of \(raw: protocolName) not found.")
                    }
                    // The `relativeOffset` here is already the correct absolute offset
                    // because `currentOffset` in the cache calculation started from the parent's size.
                    return relativeOffset
                }
                public static func offset(of field: \(raw: fieldEnumName)) -> Int {
                    // The offsets in `fieldEnumName._cachedOffsets.cache` are already absolute
                    // from the perspective of where this protocol's fields start.
                    guard let relativeOffset = \(raw: fieldEnumName)._cachedOffsets.cache[field] else {
                        fatalError("Offset for field \\(field) of \(raw: protocolName) not found.")
                    }
                    // The `relativeOffset` here is already the correct absolute offset
                    // because `currentOffset` in the cache calculation started from the parent's size.
                    return relativeOffset
                }
            }
            """
        )
        if directFields.isEmpty && protocolDecl.inheritanceClause == nil {
            let emptyExtensionDeclSyntax: ExtensionDeclSyntax = try .init(
                """
                extension \(raw: protocolName) {
                    public func offset(of field: \(raw: fieldEnumName)) -> Int {
                        // No fields, this should ideally not be callable with a valid field.
                        fatalError("Protocol \(raw: protocolName) has no layout fields.")
                    }
                    public static func offset(of field: \(raw: fieldEnumName)) -> Int {
                        // No fields, this should ideally not be callable with a valid field.
                        fatalError("Protocol \(raw: protocolName) has no layout fields.")
                    }
                }
                """
            )
            return [emptyExtensionDeclSyntax]
        }
        return [extensionDeclSyntax]
    }

    // MARK: - Helper Functions

    private struct Field {
        let name: String
        let type: TypeSyntax
    }
}

// MARK: - Error Enum

enum LayoutError: CustomStringConvertible, Error, DiagnosticMessage {
    case notAProtocol
    case internalError(String)

    var message: String {
        switch self {
        case .notAProtocol: return "@Layout can only be applied to protocols."
        case .internalError(let detail): return "Internal macro error: \(detail)."
        }
    }

    var description: String {
        return message
    }

    var diagnosticID: MessageID {
        switch self {
        case .notAProtocol: return MessageID(domain: "LayoutMacro", id: "NotAProtocol")
        case .internalError: return MessageID(domain: "LayoutMacro", id: "InternalError")
        }
    }

    var severity: DiagnosticSeverity {
        return .error
    }

    // Corrected: diag method to create SwiftDiagnostics.Diagnostic
    func diag(at node: Syntax) -> SwiftDiagnostics.Diagnostic {
        // Use the provided node, or a MissingNode if nil (though ideally a node is always provided)
        return SwiftDiagnostics.Diagnostic(node: node, message: self)
    }
}
