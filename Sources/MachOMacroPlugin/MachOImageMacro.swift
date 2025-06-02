import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

private func buildFuncDecl(of node: AttributeSyntax, funcDecl: FunctionDeclSyntax) -> FunctionDeclSyntax {
    let originalAttributes = funcDecl.attributes

    let preservedAttributes = AttributeListSyntax(
        originalAttributes.compactMap { element -> AttributeListSyntax.Element? in
            if case .attribute(let attr) = element, attr.trimmedDescription == node.trimmedDescription {
                return nil
            }
            return element
        }
    )

    let finalAttributes = preservedAttributes.with(\.trailingTrivia, .spaces(1))

    let newParameters = funcDecl.signature.parameterClause.parameters.map { param -> FunctionParameterSyntax in
        var newParam = param

        if let type = param.type.as(IdentifierTypeSyntax.self), type.name.text == "MachOFile" {
            newParam = newParam.with(\.type, TypeSyntax(IdentifierTypeSyntax(name: .identifier("MachOImage"))))
        }

        if param.firstName.text == "machOFile" {
            newParam = newParam.with(\.firstName, .identifier("machOImage"))
        }

        if let secondName = param.secondName, secondName.text == "machOFile" {
            newParam = newParam.with(\.secondName, .identifier("machOImage"))
        } else if param.firstName.text == "machOFile" && param.secondName == nil {
            newParam = newParam.with(\.firstName, .identifier("machOImage"))
        }

        if param.firstName.text == "fileOffset" {
            newParam = param.with(\.firstName, .identifier("imageOffset"))
        }

        if let secondName = param.secondName, secondName.text == "fileOffset" {
            newParam = param.with(\.secondName, .identifier("imageOffset"))
        }
        return newParam
    }
    let newParameterClause = funcDecl.signature.parameterClause.with(\.parameters, FunctionParameterListSyntax(newParameters))
    let newSignature = funcDecl.signature.with(\.parameterClause, newParameterClause)

    let rewriter = MachOBodyRewriter()
    let newBody: CodeBlockSyntax?
    if let body = funcDecl.body {
        newBody = rewriter.rewrite(body).as(CodeBlockSyntax.self)
    } else {
        newBody = nil
    }

    let newFunc = FunctionDeclSyntax(
        attributes: finalAttributes,
        modifiers: funcDecl.modifiers,
        name: funcDecl.name,
        genericParameterClause: funcDecl.genericParameterClause,
        signature: newSignature,
        genericWhereClause: funcDecl.genericWhereClause,
        body: newBody
    )
    return newFunc
}

public struct MachOImageAllMembersGeneratorMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        var generatedMembers: [DeclSyntax] = []

        for member in declaration.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else {
                continue
            }
            generatedMembers.append(DeclSyntax(buildFuncDecl(of: node, funcDecl: funcDecl)))
        }

        return generatedMembers
    }
}

public struct MachOImageGeneratorMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        if let funcDecl = declaration.as(FunctionDeclSyntax.self) {
            return [DeclSyntax(buildFuncDecl(of: node, funcDecl: funcDecl))]
        } else if let initDecl = declaration.as(InitializerDeclSyntax.self) {
            let originalAttributes = initDecl.attributes

            let preservedAttributes = AttributeListSyntax(
                originalAttributes.compactMap { element -> AttributeListSyntax.Element? in
                    if case .attribute(let attr) = element, attr.trimmedDescription == node.trimmedDescription {
                        return nil
                    }
                    return element
                }
            )
            let finalAttributes = preservedAttributes.with(\.trailingTrivia, .spaces(1))

            let newParameters = initDecl.signature.parameterClause.parameters.map { param -> FunctionParameterSyntax in
                var newParam = param

                if let type = param.type.as(IdentifierTypeSyntax.self), type.name.text == "MachOFile" {
                    newParam = newParam.with(\.type, TypeSyntax(IdentifierTypeSyntax(name: .identifier("MachOImage"))))
                }

                if param.firstName.text == "machOFile" {
                    newParam = newParam.with(\.firstName, .identifier("machOImage"))
                }

                if let secondName = param.secondName, secondName.text == "machOFile" {
                    newParam = newParam.with(\.secondName, .identifier("machOImage"))
                } else if param.firstName.text == "machOFile" && param.secondName == nil {
                    newParam = newParam.with(\.firstName, .identifier("machOImage"))
                }

                if param.firstName.text == "fileOffset" {
                    newParam = param.with(\.firstName, .identifier("imageOffset"))
                }
                
                if let secondName = param.secondName, secondName.text == "fileOffset" {
                    newParam = param.with(\.secondName, .identifier("imageOffset"))
                }
                return newParam
            }
            let newParameterClause = initDecl.signature.parameterClause.with(\.parameters, FunctionParameterListSyntax(newParameters))
            let newSignature = initDecl.signature.with(\.parameterClause, newParameterClause)

            let rewriter = MachOBodyRewriter()
            let newBody: CodeBlockSyntax?
            if let body = initDecl.body {
                newBody = rewriter.rewrite(body).as(CodeBlockSyntax.self)
            } else {
                newBody = nil
            }

            let newFunc = InitializerDeclSyntax(
                attributes: finalAttributes,
                modifiers: initDecl.modifiers,
                genericParameterClause: initDecl.genericParameterClause,
                signature: newSignature,
                genericWhereClause: initDecl.genericWhereClause,
                body: newBody
            )

            return [DeclSyntax(newFunc)]
        } else {
            return []
        }
    }
}

class MachOBodyRewriter: SyntaxRewriter {
    override func visit(_ node: DeclReferenceExprSyntax) -> ExprSyntax {
        var newNode = node
        if node.baseName.text == "machOFile" {
            newNode = node.with(\.baseName, .identifier("machOImage"))
        } else if node.baseName.text == "fileOffset" {
            newNode = node.with(\.baseName, .identifier("imageOffset"))
        }
        return ExprSyntax(newNode)
    }

//    override func visit(_ node: MemberAccessExprSyntax) -> ExprSyntax {
//        let newBase = node.base.map { self.rewrite($0).as(ExprSyntax.self)! } ?? nil
//        if let baseIdentifier = newBase?.as(DeclReferenceExprSyntax.self),
//           baseIdentifier.baseName.text == "machOImage" {
//            let memberName = node.declName.baseName.text
//            var newMemberNameToken: TokenSyntax?

//            switch memberName {
//            case "readElement":
//                newMemberNameToken = .identifier("assumingElement")
//            case "readElements":
//                newMemberNameToken = .identifier("assumingElements")
//            case "readString":
//                newMemberNameToken = .identifier("assumingString")
//            default:
//                break
//            }

//            if let newMemberNameToken = newMemberNameToken {
//                return ExprSyntax(
//                    node.with(\.base, newBase)
//                        .with(\.declName, DeclReferenceExprSyntax(baseName: newMemberNameToken))
//                )
//            }
//        }
//        return ExprSyntax(node.with(\.base, newBase))
//    }
}
