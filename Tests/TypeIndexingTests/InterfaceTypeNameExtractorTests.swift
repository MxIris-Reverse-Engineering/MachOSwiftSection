#if os(macOS)

import Testing
@testable import TypeIndexing

@Suite
struct InterfaceTypeNameExtractorTests {
    private typealias Node = InterfaceDeclarationNode

    @Test
    func topLevelTypeDeclarationsAreCollected() {
        let declarations = [
            Node(kind: .typeDeclaration, name: "NSString"),
            Node(kind: .typeDeclaration, name: "NSURLSession"),
            Node(kind: .typeAlias, name: "NSStringEncoding"),
            Node(kind: .other, name: "someGlobalFunction()"),
        ]
        #expect(InterfaceTypeNameExtractor.fullyQualifiedTypeNames(in: declarations) == [
            "NSString",
            "NSURLSession",
            "NSStringEncoding",
        ])
    }

    @Test
    func nestedTypesAreQualifiedByTheirParentChain() {
        let declarations = [
            Node(kind: .typeDeclaration, name: "Outer", children: [
                Node(kind: .typeDeclaration, name: "Inner", children: [
                    Node(kind: .typeDeclaration, name: "Innermost"),
                ]),
                Node(kind: .other, name: "someMethod()"),
            ]),
        ]
        #expect(InterfaceTypeNameExtractor.fullyQualifiedTypeNames(in: declarations) == [
            "Outer",
            "Outer.Inner",
            "Outer.Inner.Innermost",
        ])
    }

    /// The historical SwiftSyntax-based parser registered a type declared in
    /// an extension under its bare name — `extension Foo { struct Bar }`
    /// produced a `Bar` key. The extractor must qualify through the extended
    /// type instead.
    @Test
    func typesNestedInExtensionsAreQualifiedByTheExtendedTypeName() {
        let declarations = [
            Node(kind: .extension, name: "Foo", children: [
                Node(kind: .typeDeclaration, name: "Bar"),
            ]),
        ]
        #expect(InterfaceTypeNameExtractor.fullyQualifiedTypeNames(in: declarations) == ["Foo.Bar"])
    }

    @Test
    func dotQualifiedExtendedTypeNamesQualifyTransitively() {
        let declarations = [
            Node(kind: .extension, name: "Foo.Bar", children: [
                Node(kind: .typeDeclaration, name: "Baz"),
            ]),
        ]
        #expect(InterfaceTypeNameExtractor.fullyQualifiedTypeNames(in: declarations) == ["Foo.Bar.Baz"])
    }

    @Test
    func extensionsThemselvesAreNotIndexedNames() {
        let declarations = [
            Node(kind: .extension, name: "NSString", children: [
                Node(kind: .other, name: "someMethod()"),
            ]),
        ]
        #expect(InterfaceTypeNameExtractor.fullyQualifiedTypeNames(in: declarations).isEmpty)
    }

    @Test
    func otherNodesAreNeverDescendedInto() {
        let declarations = [
            Node(kind: .other, name: "someGlobalFunction()", children: [
                Node(kind: .typeDeclaration, name: "LocalTypeThatMustNotLeak"),
            ]),
        ]
        #expect(InterfaceTypeNameExtractor.fullyQualifiedTypeNames(in: declarations).isEmpty)
    }

    @Test
    func namelessDeclarationsAreSkipped() {
        let declarations = [
            Node(kind: .typeDeclaration, name: nil),
            Node(kind: .typeDeclaration, name: ""),
            Node(kind: .typeDeclaration, name: "Survivor"),
        ]
        #expect(InterfaceTypeNameExtractor.fullyQualifiedTypeNames(in: declarations) == ["Survivor"])
    }

    @Test
    func sourceKitDeclarationKindsMapOntoTheExtractorVocabulary() {
        #expect(InterfaceDeclarationNode.kind(forUIDString: "source.lang.swift.decl.struct") == .typeDeclaration)
        #expect(InterfaceDeclarationNode.kind(forUIDString: "source.lang.swift.decl.class") == .typeDeclaration)
        #expect(InterfaceDeclarationNode.kind(forUIDString: "source.lang.swift.decl.actor") == .typeDeclaration)
        #expect(InterfaceDeclarationNode.kind(forUIDString: "source.lang.swift.decl.enum") == .typeDeclaration)
        #expect(InterfaceDeclarationNode.kind(forUIDString: "source.lang.swift.decl.protocol") == .typeDeclaration)
        #expect(InterfaceDeclarationNode.kind(forUIDString: "source.lang.swift.decl.typealias") == .typeAlias)
        #expect(InterfaceDeclarationNode.kind(forUIDString: "source.lang.swift.decl.extension") == .extension)
        #expect(InterfaceDeclarationNode.kind(forUIDString: "source.lang.swift.decl.extension.struct") == .extension)
        #expect(InterfaceDeclarationNode.kind(forUIDString: "source.lang.swift.decl.function.method.instance") == .other)
        #expect(InterfaceDeclarationNode.kind(forUIDString: "source.lang.swift.decl.var.instance") == .other)
        #expect(InterfaceDeclarationNode.kind(forUIDString: "source.lang.swift.decl.enumcase") == .other)
        #expect(InterfaceDeclarationNode.kind(forUIDString: "source.lang.swift.decl.associatedtype") == .other)
    }
}

#endif
