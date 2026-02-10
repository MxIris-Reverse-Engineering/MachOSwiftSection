import Foundation
import Testing
@testable import Demangling

/// Unit tests for NodeBuilder - these are self-contained and don't depend on external binaries.
@Suite
struct NodeBuilderTests {
    // MARK: - Basic Construction

    @Test func initWithExistingNode() {
        let original = Node(kind: .type, contents: .text("Test"))
        let builder = NodeBuilder(original)
        let result = builder.node

        #expect(result.kind == .type)
        #expect(result.text == "Test")
        #expect(result !== original, "Builder should create a copy, not reference original")
    }

    @Test func initWithKindAndContents() {
        let builder = NodeBuilder(kind: .identifier, contents: .text("Foo"))
        let result = builder.node

        #expect(result.kind == .identifier)
        #expect(result.text == "Foo")
        #expect(result.children.isEmpty)
    }

    @Test func initWithChildren() {
        let child1 = Node(kind: .identifier, contents: .text("A"))
        let child2 = Node(kind: .identifier, contents: .text("B"))
        let builder = NodeBuilder(kind: .type, children: [child1, child2])
        let result = builder.node

        #expect(result.children.count == 2)
        #expect(result.children[0].text == "A")
        #expect(result.children[1].text == "B")
    }

    // MARK: - Mutating Operations (return Self)

    @Test func addChild() {
        let builder = NodeBuilder(kind: .type)
        let child = Node(kind: .identifier, contents: .text("Child"))

        let returnedBuilder = builder.addChild(child)

        #expect(returnedBuilder === builder, "Should return same builder for chaining")
        #expect(builder.node.children.count == 1)
        #expect(builder.node.children[0].text == "Child")
    }

    @Test func addChildAddsToChildren() {
        let builder = NodeBuilder(kind: .type)
        let child = Node(kind: .identifier, contents: .text("X"))

        builder.addChild(child)

        #expect(builder.node.children.count == 1)
        #expect(builder.node.children[0].text == "X")
    }

    @Test func addChildren() {
        let builder = NodeBuilder(kind: .type)
        let children = [
            Node(kind: .identifier, contents: .text("A")),
            Node(kind: .identifier, contents: .text("B")),
            Node(kind: .identifier, contents: .text("C"))
        ]

        builder.addChildren(children)

        #expect(builder.node.children.count == 3)
        #expect(builder.node.children.map { $0.text } == ["A", "B", "C"])
    }

    @Test func insertChildAtIndex() {
        let builder = NodeBuilder(kind: .type, children: [
            Node(kind: .identifier, contents: .text("A")),
            Node(kind: .identifier, contents: .text("C"))
        ])

        builder.insertChild(Node(kind: .identifier, contents: .text("B")), at: 1)

        #expect(builder.node.children.count == 3)
        #expect(builder.node.children.map { $0.text } == ["A", "B", "C"])
    }

    @Test func removeChildAtIndex() {
        let builder = NodeBuilder(kind: .type, children: [
            Node(kind: .identifier, contents: .text("A")),
            Node(kind: .identifier, contents: .text("B")),
            Node(kind: .identifier, contents: .text("C"))
        ])

        builder.removeChild(at: 1)

        #expect(builder.node.children.count == 2)
        #expect(builder.node.children.map { $0.text } == ["A", "C"])
    }

    @Test func setChildAtIndex() {
        let builder = NodeBuilder(kind: .type, children: [
            Node(kind: .identifier, contents: .text("Old"))
        ])

        builder.setChild(Node(kind: .identifier, contents: .text("New")), at: 0)

        #expect(builder.node.children[0].text == "New")
    }

    @Test func setChildren() {
        let builder = NodeBuilder(kind: .type, children: [
            Node(kind: .identifier, contents: .text("Old"))
        ])

        builder.setChildren([
            Node(kind: .identifier, contents: .text("New1")),
            Node(kind: .identifier, contents: .text("New2"))
        ])

        #expect(builder.node.children.count == 2)
        #expect(builder.node.children.map { $0.text } == ["New1", "New2"])
    }

    @Test func reverseChildren() {
        let builder = NodeBuilder(kind: .type, children: [
            Node(kind: .identifier, contents: .text("A")),
            Node(kind: .identifier, contents: .text("B")),
            Node(kind: .identifier, contents: .text("C"))
        ])

        builder.reverseChildren()

        #expect(builder.node.children.map { $0.text } == ["C", "B", "A"])
    }

    @Test func reverseFirstN() {
        let builder = NodeBuilder(kind: .type, children: [
            Node(kind: .identifier, contents: .text("A")),
            Node(kind: .identifier, contents: .text("B")),
            Node(kind: .identifier, contents: .text("C")),
            Node(kind: .identifier, contents: .text("D"))
        ])

        builder.reverseFirst(2)

        #expect(builder.node.children.map { $0.text } == ["B", "A", "C", "D"])
    }

    // MARK: - Non-mutating Operations (return new Node)

    @Test func addingChildReturnsNewNode() {
        let builder = NodeBuilder(kind: .type)
        let child = Node(kind: .identifier, contents: .text("Child"))

        let newNode = builder.addingChild(child)

        #expect(newNode !== builder.node, "Should return a new node")
        #expect(newNode.children.count == 1)
        #expect(builder.node.children.isEmpty, "Original should be unchanged")
    }

    @Test func removingChildReturnsNewNode() {
        let builder = NodeBuilder(kind: .type, children: [
            Node(kind: .identifier, contents: .text("A")),
            Node(kind: .identifier, contents: .text("B"))
        ])

        let newNode = builder.removingChild(at: 0)

        #expect(newNode.children.count == 1)
        #expect(newNode.children[0].text == "B")
        #expect(builder.node.children.count == 2, "Original should be unchanged")
    }

    @Test func insertingChildReturnsNewNode() {
        let builder = NodeBuilder(kind: .type, children: [
            Node(kind: .identifier, contents: .text("A")),
            Node(kind: .identifier, contents: .text("C"))
        ])

        let newNode = builder.insertingChild(Node(kind: .identifier, contents: .text("B")), at: 1)

        #expect(newNode.children.count == 3)
        #expect(newNode.children.map { $0.text } == ["A", "B", "C"])
        #expect(builder.node.children.count == 2, "Original should be unchanged")
    }

    @Test func replacingDescendant() {
        let grandchild = Node(kind: .identifier, contents: .text("Old"))
        let child = Node(kind: .type, children: [grandchild])
        let builder = NodeBuilder(kind: .global, children: [child])

        let newGrandchild = Node(kind: .identifier, contents: .text("New"))
        let newNode = builder.replacingDescendant(grandchild, with: newGrandchild)

        #expect(newNode.children[0].children[0].text == "New")
        #expect(builder.node.children[0].children[0].text == "Old", "Original should be unchanged")
    }

    // MARK: - Transformations

    @Test func changingKind() {
        let builder = NodeBuilder(kind: .type, contents: .text("Test"))

        let newNode = builder.changingKind(.identifier)

        #expect(newNode.kind == .identifier)
        #expect(newNode.text == "Test", "Contents should be preserved")
    }

    @Test func changingKindWithAdditionalChildren() {
        let builder = NodeBuilder(kind: .type, children: [
            Node(kind: .identifier, contents: .text("Existing"))
        ])

        let newNode = builder.changingKind(.global, additionalChildren: [
            Node(kind: .identifier, contents: .text("New"))
        ])

        #expect(newNode.kind == .global)
        #expect(newNode.children.count == 2)
        #expect(newNode.children.map { $0.text } == ["Existing", "New"])
    }

    @Test func copy() {
        let original = Node(kind: .type, contents: .text("Test"), children: [
            Node(kind: .identifier, contents: .text("Child"))
        ])
        let builder = NodeBuilder(original)

        let copy = builder.copy()

        #expect(copy !== original)
        #expect(copy.kind == original.kind)
        #expect(copy.text == original.text)
        #expect(copy.children.count == original.children.count)
        #expect(copy.children[0] !== original.children[0], "Children should also be copied")
    }

    // MARK: - Edge Cases

    @Test func removeChildAtInvalidIndex() {
        let builder = NodeBuilder(kind: .type, children: [
            Node(kind: .identifier, contents: .text("A"))
        ])

        builder.removeChild(at: 10)  // Should not crash

        #expect(builder.node.children.count == 1, "Should remain unchanged")
    }

    @Test func setChildAtInvalidIndex() {
        let builder = NodeBuilder(kind: .type)

        builder.setChild(Node(kind: .identifier), at: 0)  // Should not crash

        #expect(builder.node.children.isEmpty, "Should remain unchanged")
    }

    @Test func chainedOperations() {
        let result = NodeBuilder(kind: .global)
            .addChild(Node(kind: .type))
            .addChild(Node(kind: .identifier, contents: .text("A")))
            .addChild(Node(kind: .identifier, contents: .text("B")))
            .removeChild(at: 0)
            .node

        #expect(result.children.count == 2)
        #expect(result.children.map { $0.text } == ["A", "B"])
    }
}
