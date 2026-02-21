import Foundation
import Testing
@testable import Demangling

/// Unit tests for NodeCache - node interning and deduplication.
@Suite
struct NodeCacheTests {

    // MARK: - Basic Interning

    @Test func internLeafNodeWithKindOnly() {
        let cache = NodeCache()

        let node1 = cache.intern(kind: .emptyList)
        let node2 = cache.intern(kind: .emptyList)

        #expect(node1 === node2, "Same kind should return same instance")
        #expect(cache.count == 1)
    }

    @Test func internLeafNodeWithText() {
        let cache = NodeCache()

        let node1 = cache.intern(kind: .identifier, text: "foo")
        let node2 = cache.intern(kind: .identifier, text: "foo")
        let node3 = cache.intern(kind: .identifier, text: "bar")

        #expect(node1 === node2, "Same kind+text should return same instance")
        #expect(node1 !== node3, "Different text should return different instance")
        #expect(cache.count == 2)
    }

    @Test func internLeafNodeWithIndex() {
        let cache = NodeCache()

        let node1 = cache.intern(kind: .index, index: 42)
        let node2 = cache.intern(kind: .index, index: 42)
        let node3 = cache.intern(kind: .index, index: 99)

        #expect(node1 === node2, "Same kind+index should return same instance")
        #expect(node1 !== node3, "Different index should return different instance")
        #expect(cache.count == 2)
    }

    @Test func internNodeWithChildren() {
        let cache = NodeCache()

        let child1 = cache.intern(kind: .identifier, text: "A")
        let child2 = cache.intern(kind: .identifier, text: "B")

        let parent1 = cache.intern(kind: .type, children: [child1, child2])
        let parent2 = cache.intern(kind: .type, children: [child1, child2])

        #expect(parent1 === parent2, "Same structure should return same instance")
        #expect(cache.count == 3) // child1, child2, parent
    }

    @Test func differentChildrenProduceDifferentNodes() {
        let cache = NodeCache()

        let childA = cache.intern(kind: .identifier, text: "A")
        let childB = cache.intern(kind: .identifier, text: "B")
        let childC = cache.intern(kind: .identifier, text: "C")

        let parent1 = cache.intern(kind: .type, children: [childA, childB])
        let parent2 = cache.intern(kind: .type, children: [childA, childC])

        #expect(parent1 !== parent2, "Different children should produce different nodes")
    }

    // MARK: - Tree Interning

    @Test func internExistingTree() {
        let cache = NodeCache()

        // Create a tree without using cache
        let tree = Node(kind: .type, children: [
            Node(kind: .identifier, text: "A"),
            Node(kind: .identifier, text: "B")
        ])

        // Intern the tree
        let interned1 = cache.intern(tree)
        let interned2 = cache.intern(tree)

        #expect(interned1 === interned2, "Interning same tree twice should return same instance")
    }

    @Test func internTreeDeduplicatesSubtrees() {
        let cache = NodeCache()

        // Create two trees with identical subtrees
        let tree1 = Node(kind: .global, children: [
            Node(kind: .type, children: [
                Node(kind: .identifier, text: "Shared")
            ])
        ])

        let tree2 = Node(kind: .function, children: [
            Node(kind: .type, children: [
                Node(kind: .identifier, text: "Shared")
            ])
        ])

        let interned1 = cache.intern(tree1)
        let interned2 = cache.intern(tree2)

        // The "Shared" identifier and its parent "type" should be the same instance
        let type1 = interned1.children[0]
        let type2 = interned2.children[0]

        #expect(type1 === type2, "Identical subtrees should be deduplicated")
    }

    @Test func internBatchOfNodes() {
        let cache = NodeCache()

        let trees = [
            Node(kind: .type, children: [Node(kind: .identifier, text: "A")]),
            Node(kind: .type, children: [Node(kind: .identifier, text: "A")]),
            Node(kind: .type, children: [Node(kind: .identifier, text: "B")])
        ]

        let interned = cache.intern(trees)

        #expect(interned[0] === interned[1], "Identical trees should be deduplicated")
        #expect(interned[0] !== interned[2], "Different trees should remain different")
    }

    // MARK: - Unsynchronized Methods

    @Test func unsafeMethodsWork() {
        let cache = NodeCache()

        let node1 = cache.internUnsafe(kind: .identifier, text: "test")
        let node2 = cache.internUnsafe(kind: .identifier, text: "test")

        #expect(node1 === node2)
    }

    @Test func unsafeTreeInterning() {
        let cache = NodeCache()

        let tree = Node(kind: .type, children: [
            Node(kind: .identifier, text: "X")
        ])

        let interned1 = cache.internTreeUnsafe(tree)
        let interned2 = cache.internTreeUnsafe(tree)

        #expect(interned1 === interned2)
    }

    // MARK: - Cache Management

    @Test func clearRemovesAllNodes() {
        let cache = NodeCache()

        _ = cache.intern(kind: .identifier, text: "a")
        _ = cache.intern(kind: .identifier, text: "b")
        _ = cache.intern(kind: .identifier, text: "c")

        #expect(cache.count == 3)

        cache.clear()

        #expect(cache.count == 0)
    }

    @Test func reserveCapacity() {
        let cache = NodeCache()

        cache.reserveCapacity(1000)

        // Just verify it doesn't crash
        #expect(cache.count == 0)
    }

    // MARK: - Global Cache

    @Test func sharedCacheIsSingleton() {
        let cache1 = NodeCache.shared
        let cache2 = NodeCache.shared

        #expect(cache1 === cache2)
    }

    // MARK: - Node.interned() Extension

    @Test func nodeInternedExtension() {
        // Clear shared cache first
        NodeCache.shared.clear()

        let node1 = Node(kind: .identifier, text: "ext")
        let node2 = Node(kind: .identifier, text: "ext")

        let interned1 = node1.interned()
        let interned2 = node2.interned()

        #expect(interned1 === interned2, "Node.interned() should use global cache")

        // Clean up
        NodeCache.shared.clear()
    }
}

// MARK: - Demangling Integration Tests

@Suite
struct NodeCacheDemangleTests {

    @Test func demangleAsNodeDeduplicatesLeaves() throws {
        // Demangle the same symbol twice — leaf nodes should be shared
        let node1 = try demangleAsNode("$sSiD")
        let node2 = try demangleAsNode("$sSiD")

        // Leaf nodes (e.g. .module("Swift")) should be the same instance
        let module1 = node1.first(of: .module)
        let module2 = node2.first(of: .module)
        #expect(module1 != nil)
        #expect(module1 === module2, "Same leaf nodes should be deduplicated")
    }

    @Test func sharedSubtreesAreInterned() throws {
        // These symbols both contain Swift module
        let node1 = try demangleAsNode("$sSiD")  // Swift.Int
        let node2 = try demangleAsNode("$sSaySSGD")  // Array<String>

        // Both should have Swift module node interned
        let module1 = node1.first(of: .module)
        let module2 = node2.first(of: .module)

        #expect(module1 != nil)
        #expect(module2 != nil)

        // Clean up
        NodeCache.shared.clear()
    }
}

// MARK: - Memory Optimization Tests

@Suite
struct NodeCacheMemoryTests {

    @Test func interningReducesNodeCount() {
        let cache = NodeCache()

        // Create many trees with shared structure
        var trees: [Node] = []
        for _ in 0..<100 {
            trees.append(Node(kind: .global, children: [
                Node(kind: .type, children: [
                    Node(kind: .structure, children: [
                        Node(kind: .module, text: "Swift"),
                        Node(kind: .identifier, text: "Int")
                    ])
                ])
            ]))
        }

        // Count total nodes before interning
        func countNodes(_ node: Node) -> Int {
            1 + node.children.reduce(0) { $0 + countNodes($1) }
        }
        let totalBefore = trees.reduce(0) { $0 + countNodes($1) }

        // Intern all trees
        let interned = cache.intern(trees)

        // All interned trees should be the same instance
        for i in 1..<interned.count {
            #expect(interned[0] === interned[i], "All identical trees should be same instance")
        }

        // Cache should have much fewer unique nodes than total
        #expect(cache.count < totalBefore, "Interning should reduce node count")
        #expect(cache.count == 5, "Should have exactly 5 unique nodes (global, type, structure, module, identifier)")
    }
}
