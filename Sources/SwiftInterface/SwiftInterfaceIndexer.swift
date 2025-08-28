import Foundation
import SwiftSyntax
import SwiftParser

final class SwiftInterfaceIndexer {
    let sourceFile: SourceFileSyntax

    var typeInfos: [TypeInfo] = []

    init(contents: String) throws {
        var parser = SwiftParser.Parser(contents)
        self.sourceFile = .parse(from: &parser)
    }

    func index() {
        let visitor = IndexerVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        typeInfos = visitor.indexedTypes
    }

    // MARK: - Data Models to store indexed information

    // Represents the kind of a type declaration
    enum TypeKind: String, CustomStringConvertible {
        case `struct`
        case `class`
        case `enum`
        case `protocol`

        var description: String {
            return rawValue
        }
    }

    // Represents the kind of a member within a type
    enum MemberKind: String, CustomStringConvertible {
        case `property`
        case `method`
        case `initializer`
        case `subscript`
        case `associatedType` // For protocols
        case `enumCase` // For enums

        var description: String {
            return rawValue
        }
    }

    // Stores information about a single member (property, method, etc.)
    struct MemberInfo: CustomStringConvertible {
        let name: String
        let kind: MemberKind

        var description: String {
            return "      - \(name) (kind: \(kind))"
        }
    }

    // Stores information about a top-level type declaration
    struct TypeInfo: CustomStringConvertible {
        let name: String
        let kind: TypeKind
        var members: [MemberInfo] = []

        var description: String {
            var desc = "Found \(kind) `\(name)` with \(members.count) members:"
            if !members.isEmpty {
                desc += "\n"
                desc += members.map { $0.description }.joined(separator: "\n")
            }
            return desc
        }
    }

    // MARK: - The Core Indexer using SyntaxVisitor

    final class IndexerVisitor: SyntaxVisitor {
        // An array to store all the top-level type information we find.
        var indexedTypes: [TypeInfo] = []

        // The initializer requires a viewMode, `.sourceAccurate` is a good default.
        override init(viewMode: SyntaxTreeViewMode) {
            super.init(viewMode: viewMode)
        }

        // MARK: - Visit Methods for Top-Level Declarations

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            // Extract the name of the struct
            let name = node.name.text
            var typeInfo = TypeInfo(name: name, kind: .struct)

            // Visit the members of this struct
            typeInfo.members = visitMembers(node.memberBlock.members)

            indexedTypes.append(typeInfo)

            // We don't need to visit children of this node further because we handled it.
            return .skipChildren
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            // Extract the name of the class
            let name = node.name.text
            var typeInfo = TypeInfo(name: name, kind: .class)

            // Visit the members of this class
            typeInfo.members = visitMembers(node.memberBlock.members)

            indexedTypes.append(typeInfo)
            return .skipChildren
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            // Extract the name of the enum
            let name = node.name.text
            var typeInfo = TypeInfo(name: name, kind: .enum)

            // Visit the members of this enum
            typeInfo.members = visitMembers(node.memberBlock.members)

            indexedTypes.append(typeInfo)
            return .skipChildren
        }

        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            // Extract the name of the protocol
            let name = node.name.text
            var typeInfo = TypeInfo(name: name, kind: .protocol)

            // Visit the members of this protocol
            typeInfo.members = visitMembers(node.memberBlock.members)

            indexedTypes.append(typeInfo)
            return .skipChildren
        }

        // MARK: - Helper to process members

        private func visitMembers(_ members: MemberBlockItemListSyntax) -> [MemberInfo] {
            var memberInfos: [MemberInfo] = []

            for member in members {
                // Each member is a `MemberDeclListItemSyntax`, we need to look at its `decl`.
                switch member.decl.kind {
                case .variableDecl:
                    // This is a property declaration (let, var)
                    if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                        // A single `let a, b: Int` has multiple bindings.
                        for binding in varDecl.bindings {
                            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                                let propertyName = pattern.identifier.text
                                memberInfos.append(MemberInfo(name: propertyName, kind: .property))
                            }
                        }
                    }

                case .functionDecl:
                    // This is a method declaration
                    if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                        let methodName = funcDecl.name.text + funcDecl.signature.description
                        memberInfos.append(MemberInfo(name: methodName, kind: .method))
                    }

                case .initializerDecl:
                    // This is an initializer (init)
                    if let initDecl = member.decl.as(InitializerDeclSyntax.self) {
                        let initName = "init" + initDecl.signature.description
                        memberInfos.append(MemberInfo(name: initName, kind: .initializer))
                    }

                case .subscriptDecl:
                    // This is a subscript
                    if let subscriptDecl = member.decl.as(SubscriptDeclSyntax.self) {
                        let subscriptName = "subscript" + subscriptDecl.parameterClause.description
                        memberInfos.append(MemberInfo(name: subscriptName, kind: .subscript))
                    }

                case .associatedTypeDecl:
                    // This is an associated type (in a protocol)
                    if let assocTypeDecl = member.decl.as(AssociatedTypeDeclSyntax.self) {
                        let assocTypeName = assocTypeDecl.name.text
                        memberInfos.append(MemberInfo(name: assocTypeName, kind: .associatedType))
                    }

                case .enumCaseDecl:
                    // This is an enum case
                    if let enumCaseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                        for element in enumCaseDecl.elements {
                            let caseName = element.name.text
                            memberInfos.append(MemberInfo(name: caseName, kind: .enumCase))
                        }
                    }

                default:
                    // We can handle other kinds of members here if needed (e.g., typealias)
                    break
                }
            }
            return memberInfos
        }
    }
}
