import Foundation
import Testing
@testable import Demangling

/// Unit tests for Node - self-contained, no external dependencies.
@Suite
struct NodeTests {
    // MARK: - Initialization

    @Test func nodeWithKindOnly() {
        let node = Node(kind: .type)

        #expect(node.kind == .type)
        #expect(node.contents == .none)
        #expect(node.children.isEmpty)
    }

    @Test func nodeWithTextContents() {
        let node = Node(kind: .identifier, contents: .text("Foo"))

        #expect(node.kind == .identifier)
        #expect(node.text == "Foo")
    }

    @Test func nodeWithIndexContents() {
        let node = Node(kind: .index, contents: .index(42))

        #expect(node.kind == .index)
        #expect(node.index == 42)
    }

    @Test func nodeWithChildren() {
        let child1 = Node(kind: .identifier, contents: .text("A"))
        let child2 = Node(kind: .identifier, contents: .text("B"))
        let parent = Node(kind: .type, children: [child1, child2])

        #expect(parent.children.count == 2)
        #expect(parent.children[0].text == "A")
        #expect(parent.children[1].text == "B")
    }

    // MARK: - Result Builder Syntax

    @Test func resultBuilderSyntax() {
        let node = Node(kind: .type) {
            Node(kind: .identifier, contents: .text("First"))
            Node(kind: .identifier, contents: .text("Second"))
        }

        #expect(node.children.count == 2)
        #expect(node.children[0].text == "First")
        #expect(node.children[1].text == "Second")
    }

    @Test func nestedResultBuilderSyntax() {
        let node = Node(kind: .type) {
            Node(kind: .dependentMemberType) {
                Node(kind: .dependentGenericParamType) {
                    Node(kind: .index, contents: .index(0))
                    Node(kind: .index, contents: .index(0))
                }
                Node(kind: .dependentAssociatedTypeRef) {
                    Node(kind: .identifier, contents: .text("Tail"))
                }
            }
        }

        #expect(node.kind == .type)
        #expect(node.children.count == 1)

        let memberType = node.children[0]
        #expect(memberType.kind == .dependentMemberType)
        #expect(memberType.children.count == 2)

        let paramType = memberType.children[0]
        #expect(paramType.kind == .dependentGenericParamType)
        #expect(paramType.text == "A")
        #expect(paramType.children.count == 2)

        let assocTypeRef = memberType.children[1]
        #expect(assocTypeRef.kind == .dependentAssociatedTypeRef)
        #expect(assocTypeRef.children[0].text == "Tail")
    }

    // MARK: - Copy

    @Test func copyCreatesDeepCopy() {
        let child = Node(kind: .identifier, contents: .text("Child"))
        let original = Node(kind: .type, contents: .text("Parent"), children: [child])

        let copy = original.copy()

        #expect(copy !== original)
        #expect(copy.kind == original.kind)
        #expect(copy.text == original.text)
        #expect(copy.children.count == 1)
        #expect(copy.children[0] !== child, "Child should be a new instance")
        #expect(copy.children[0].text == "Child")
    }

    // MARK: - Contents Accessors

    @Test func textAccessor() {
        let textNode = Node(kind: .identifier, contents: .text("Hello"))
        let indexNode = Node(kind: .index, contents: .index(42))
        let noneNode = Node(kind: .type)

        #expect(textNode.text == "Hello")
        #expect(indexNode.text == nil)
        #expect(noneNode.text == nil)
    }

    @Test func indexAccessor() {
        let textNode = Node(kind: .identifier, contents: .text("Hello"))
        let indexNode = Node(kind: .index, contents: .index(42))
        let noneNode = Node(kind: .type)

        #expect(textNode.index == nil)
        #expect(indexNode.index == 42)
        #expect(noneNode.index == nil)
    }

    // MARK: - Child Access Helpers

    @Test func childrenAtIndex() {
        let node = Node(kind: .type, children: [
            Node(kind: .identifier, contents: .text("A")),
            Node(kind: .identifier, contents: .text("B")),
            Node(kind: .identifier, contents: .text("C"))
        ])

        #expect(node.children.at(0)?.text == "A")
        #expect(node.children.at(1)?.text == "B")
        #expect(node.children.at(2)?.text == "C")
        #expect(node.children.at(3) == nil)
        #expect(node.children.at(-1) == nil)
    }

    @Test func firstAndSecondChild() {
        let node = Node(kind: .type, children: [
            Node(kind: .identifier, contents: .text("First")),
            Node(kind: .identifier, contents: .text("Second"))
        ])

        #expect(node.children.first?.text == "First")
        #expect(node.children.second?.text == "Second")
    }

    // MARK: - Kind Checking

    @Test func isKindOf() {
        let node = Node(kind: .type)

        #expect(node.isKind(of: .type))
        #expect(!node.isKind(of: .identifier))
    }

    @Test func isKindOfMultiple() {
        let node = Node(kind: .type)

        #expect(node.isKind(of: .type, .identifier))
        #expect(node.isKind(of: .identifier, .type))
        #expect(!node.isKind(of: .identifier, .module))
    }

    // MARK: - Tree Traversal

    @Test func firstOfKind() {
        let node = Node(kind: .global, children: [
            Node(kind: .type, children: [
                Node(kind: .identifier, contents: .text("Found"))
            ])
        ])

        let found = node.first(of: .identifier)

        #expect(found?.text == "Found")
    }

    @Test func firstOfKindNotFound() {
        let node = Node(kind: .global, children: [
            Node(kind: .type)
        ])

        #expect(node.first(of: .identifier) == nil)
    }

    @Test func allOfKind() {
        let node = Node(kind: .global, children: [
            Node(kind: .identifier, contents: .text("A")),
            Node(kind: .type, children: [
                Node(kind: .identifier, contents: .text("B"))
            ]),
            Node(kind: .identifier, contents: .text("C"))
        ])

        let identifiers = node.all(of: .identifier)

        #expect(identifiers.count == 3)
        #expect(identifiers.map { $0.text } == ["A", "B", "C"])
    }

    @Test func allOfMultipleKinds() {
        let node = Node(kind: .global, children: [
            Node(kind: .identifier, contents: .text("Id")),
            Node(kind: .module, contents: .text("Mod")),
            Node(kind: .type)
        ])

        let found = node.all(of: .identifier, .module)

        #expect(found.count == 2)
    }

    // MARK: - Contents Hashable

    @Test func contentsHashable() {
        let contents1 = Node.Contents.text("Test")
        let contents2 = Node.Contents.text("Test")
        let contents3 = Node.Contents.text("Other")
        let contents4 = Node.Contents.index(42)
        let contents5 = Node.Contents.index(42)
        let contents6 = Node.Contents.none
        let contents7 = Node.Contents.none

        #expect(contents1 == contents2)
        #expect(contents1 != contents3)
        #expect(contents4 == contents5)
        #expect(contents6 == contents7)
        #expect(contents1 != contents4)
        #expect(contents1 != contents6)
    }

    // MARK: - Child Addition

    @Test func childAddition() {
        let parent = Node(kind: .type)
        let child = Node(kind: .identifier, contents: .text("X"))

        let result = parent.addingChild(child)

        #expect(result.children.count == 1)
        #expect(result.children[0].text == "X")
    }
}

// MARK: - Demangling Integration Tests

@Suite
struct NodeDemanglingTests {
    @Test(arguments: [
        // (mangled, expectedFirstChildKind)
        // Note: $sSi (Swift.Int) demangles to Global > Structure (not Type)
        ("$sSi", Node.Kind.structure),           // Swift.Int
        ("$sSS", Node.Kind.structure),           // Swift.String
        ("$sSa", Node.Kind.structure),           // Swift.Array
    ])
    func basicTypeDemangling(mangled: String, expectedKind: Node.Kind) throws {
        let node = try demangleAsNode(mangled)

        #expect(node.kind == .global)
        #expect(node.children.count == 1)

        let firstChild = node.children[0]
        #expect(firstChild.kind == expectedKind)
    }

    @Test(arguments: [
        ("$sSiD", "Swift.Int"),
        ("$sSSD", "Swift.String"),
        ("$sSbD", "Swift.Bool"),
        ("$sSfD", "Swift.Float"),
        ("$sSdD", "Swift.Double"),
    ])
    func basicTypePrinting(mangled: String, expected: String) throws {
        let node = try demangleAsNode(mangled)
        let result = node.print(using: .default)

        #expect(result == expected)
    }

    @Test(arguments: [
        ("$s4Main3FooVD", "Main.Foo"),
        ("$s4Main3BarCD", "Main.Bar"),
        ("$s4Main3BazOD", "Main.Baz"),
    ])
    func customTypePrinting(mangled: String, expected: String) throws {
        let node = try demangleAsNode(mangled)
        let result = node.print(using: .default)

        #expect(result == expected)
    }

    @Test func functionSignatureDemangling() throws {
        let mangled = "$s4Main3fooyySiF"  // Main.foo(Swift.Int) -> ()
        let node = try demangleAsNode(mangled)

        #expect(node.kind == .global)
        let functionNode = node.first(of: .function)
        #expect(functionNode != nil)
    }

    @Test func genericTypeDemangling() throws {
        let mangled = "$sSaySSGD"  // [String]
        let node = try demangleAsNode(mangled)
        let result = node.print(using: .default.union(.synthesizeSugarOnTypes))

        #expect(result == "[Swift.String]")
    }

    @Test func optionalTypeDemangling() throws {
        let mangled = "$sSiSgD"  // Int?
        let node = try demangleAsNode(mangled)
        let result = node.print(using: .default.union(.synthesizeSugarOnTypes))

        #expect(result == "Swift.Int?")
    }

    @Test func dictionaryTypeDemangling() throws {
        let mangled = "$sSDySSSiGD"  // [String: Int]
        let node = try demangleAsNode(mangled)
        let result = node.print(using: .default.union(.synthesizeSugarOnTypes))

        #expect(result == "[Swift.String : Swift.Int]")
    }
}

struct NodeChildrenTests {
    
    @Test func size() async throws {
        print(MemoryLayout<Node.Kind>.size)
    }
}
