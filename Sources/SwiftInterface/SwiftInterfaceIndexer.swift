import Foundation
import SwiftSyntax
import SwiftParser
import FoundationToolbox
import OrderedCollections

@available(iOS, unavailable)
@available(tvOS, unavailable)
@available(watchOS, unavailable)
@available(visionOS, unavailable)
final class SwiftInterfaceIndexer: Sendable {

    let moduleName: String
    
    let sourceFileSyntax: SourceFileSyntax

    @Mutex
    var typeInfos: [TypeInfo] = []

    @Mutex
    var importInfos: [ImportInfo] = []
    
    var subModuleNames: OrderedSet<String> {
        var results: OrderedSet<String> = []
        for importInfo in importInfos {
            let moduleComponents = importInfo.moduleName.components(separatedBy: ".")
            if moduleComponents.first == moduleName {
                results.append(importInfo.moduleName)
            }
        }
        return results
    }
    
    init(file: SwiftInterfaceFile) throws {
        self.moduleName = file.moduleName
        var parser = try SwiftParser.Parser(.init(contentsOfFile: file.path, encoding: .utf8))
        self.sourceFileSyntax = .parse(from: &parser)
    }
    
    init(file: SwiftInterfaceGeneratedFile) {
        self.moduleName = file.moduleName
        var parser = SwiftParser.Parser(file.contents)
        self.sourceFileSyntax = .parse(from: &parser)
    }

    nonisolated func index() async throws {
        let visitor = IndexerVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFileSyntax)
        typeInfos = visitor.typeInfos
        importInfos = visitor.importInfos
    }

    // MARK: - Data Models to store indexed information

    // Represents the kind of a type declaration
    enum TypeKind: String, CustomStringConvertible, Sendable {
        case `struct`
        case `class`
        case `enum`
        case `protocol`

        var description: String {
            return rawValue
        }
    }

    // Represents the kind of a member within a type
    enum MemberKind: String, CustomStringConvertible, Sendable {
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
    struct MemberInfo: CustomStringConvertible, Sendable {
        let name: String
        let kind: MemberKind

        var description: String {
            return "      - \(name) (kind: \(kind))"
        }
    }

    // Stores information about a top-level type declaration
    struct TypeInfo: CustomStringConvertible, Sendable {
        let name: String
        let kind: TypeKind
        var members: [MemberInfo] = []
        var genericParams: [String] = []

        var description: String {
            var desc = "Found \(kind) `\(name)` with \(members.count) members:"
            desc += genericParams.isEmpty ? "" : " <\(genericParams.joined(separator: ", "))>"
            if !members.isEmpty {
                desc += "\n"
                desc += members.map { $0.description }.joined(separator: "\n")
            }
            return desc
        }
    }

    struct ImportInfo: CustomStringConvertible, Sendable {
        let moduleName: String

        var description: String {
            return "Import \(moduleName)"
        }
    }
    
    // MARK: - The Core Indexer using SyntaxVisitor

    private final class IndexerVisitor: SyntaxVisitor, @unchecked Sendable {
        // An array to store all the top-level type information we find.

        @Mutex
        var typeInfos: [TypeInfo] = []

        @Mutex
        var importInfos: [ImportInfo] = []
        
        // The initializer requires a viewMode, `.sourceAccurate` is a good default.
        override init(viewMode: SyntaxTreeViewMode) {
            super.init(viewMode: viewMode)
        }
        
        override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
            var moduleName = ""
            for (index, component) in node.path.enumerated() {
                if index != 0 {
                    moduleName.append(".")
                }
                moduleName.append(component.name.text)
            }
            importInfos.append(ImportInfo(moduleName: moduleName))
            return .visitChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            // Extract the name of the struct
            let name = node.name.text
            var typeInfo = TypeInfo(name: fullyQualifiedName(for: node, with: name), kind: .struct)

            // Visit the members of this struct
            typeInfo.members = visitMembers(node.memberBlock.members)
            typeInfo.genericParams = node.genericParameterClause?.parameters.map { $0.name.text } ?? []
            typeInfos.append(typeInfo)

            // We don't need to visit children of this node further because we handled it.
            return .visitChildren
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            // Extract the name of the class
            let name = node.name.text
            var typeInfo = TypeInfo(name: fullyQualifiedName(for: node, with: name), kind: .class)

            // Visit the members of this class
            typeInfo.members = visitMembers(node.memberBlock.members)
            typeInfo.genericParams = node.genericParameterClause?.parameters.map { $0.name.text } ?? []

            typeInfos.append(typeInfo)
            return .visitChildren
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            // Extract the name of the enum
            let name = node.name.text
            var typeInfo = TypeInfo(name: fullyQualifiedName(for: node, with: name), kind: .enum)

            // Visit the members of this enum
            typeInfo.members = visitMembers(node.memberBlock.members)
            typeInfo.genericParams = node.genericParameterClause?.parameters.map { $0.name.text } ?? []

            typeInfos.append(typeInfo)
            return .visitChildren
        }

        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            // Extract the name of the protocol
            let name = node.name.text
            var typeInfo = TypeInfo(name: fullyQualifiedName(for: node, with: name), kind: .protocol)

            // Visit the members of this protocol
            typeInfo.members = visitMembers(node.memberBlock.members)

            typeInfos.append(typeInfo)
            return .visitChildren
        }

        // MARK: - Visit Methods for Top-Level Declarations

        private func fullyQualifiedName(for node: SyntaxProtocol, with baseName: String) -> String {
            var parentPath: [String] = []
            var currentNode: Syntax? = node.parent

            while let current = currentNode {
                // Check if the parent is a type declaration and get its name
                let parentName: String? = {
                    if let structDecl = current.as(StructDeclSyntax.self) {
                        return structDecl.name.text
                    } else if let classDecl = current.as(ClassDeclSyntax.self) {
                        return classDecl.name.text
                    } else if let enumDecl = current.as(EnumDeclSyntax.self) {
                        return enumDecl.name.text
                    } else if let protocolDecl = current.as(ProtocolDeclSyntax.self) {
                        return protocolDecl.name.text
                    }
                    return nil
                }()

                if let name = parentName {
                    // Prepend the name, because we are traversing from inside out
                    parentPath.insert(name, at: 0)
                }

                currentNode = current.parent
            }

            if parentPath.isEmpty {
                return baseName
            } else {
                return parentPath.joined(separator: ".") + "." + baseName
            }
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
