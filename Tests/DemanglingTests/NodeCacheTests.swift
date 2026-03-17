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

        // Tree nodes (with children) are NOT cached — each call creates a new instance
        #expect(parent1 !== parent2, "Nodes with children should not be cached")
        // Only leaf nodes are cached
        #expect(cache.count == 2) // child1, child2
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

        // Intern the tree — only leaf nodes get deduplicated, tree roots are not cached
        let interned1 = cache.intern(tree)
        let interned2 = cache.intern(tree)

        // Tree roots are not cached, but leaf children should be shared
        #expect(interned1.children[0] === interned2.children[0], "Leaf children should be deduplicated")
        #expect(interned1.children[1] === interned2.children[1], "Leaf children should be deduplicated")
    }

    @Test func internTreeDeduplicatesLeafNodes() {
        let cache = NodeCache()

        // Create two trees with identical leaf nodes
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

        // The "Shared" leaf identifier should be the same instance across both trees
        let leaf1 = interned1.children[0].children[0]
        let leaf2 = interned2.children[0].children[0]

        #expect(leaf1 === leaf2, "Identical leaf nodes should be deduplicated")

        // But the parent .type nodes (with children) should NOT be the same instance
        let type1 = interned1.children[0]
        let type2 = interned2.children[0]
        #expect(type1 !== type2, "Tree nodes with children are not cached")
    }

    @Test func internBatchOfNodes() {
        let cache = NodeCache()

        let trees = [
            Node(kind: .type, children: [Node(kind: .identifier, text: "A")]),
            Node(kind: .type, children: [Node(kind: .identifier, text: "A")]),
            Node(kind: .type, children: [Node(kind: .identifier, text: "B")])
        ]

        let interned = cache.intern(trees)

        // Tree roots are not cached, so they are different instances
        #expect(interned[0] !== interned[1], "Tree nodes with children are not cached")
        // But their shared leaf children should be the same instance
        #expect(interned[0].children[0] === interned[1].children[0], "Identical leaf children should be deduplicated")
        #expect(interned[0].children[0] !== interned[2].children[0], "Different leaf children should remain different")
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

        // Tree roots are not cached, but leaf children should be shared
        #expect(interned1.children[0] === interned2.children[0], "Leaf children should be deduplicated")
    }

    // MARK: - Cache Management

    @Test func clearRemovesUserNodes() {
        let cache = NodeCache()

        let internedBeforeClear = cache.intern(kind: .identifier, text: "a")
        _ = cache.intern(kind: .identifier, text: "b")
        _ = cache.intern(kind: .identifier, text: "c")

        #expect(cache.count == 3)

        cache.clear()

        // clear() calls registerFactorySingletons(), so count equals the number of factory singletons
        #expect(cache.count > 0, "Factory singletons should be re-registered after clear")

        // Re-interning after clear should produce a different instance than before clear
        let internedAfterClear = cache.intern(kind: .identifier, text: "a")
        #expect(internedAfterClear !== internedBeforeClear, "Clear should remove previously interned user nodes")
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

    @Test func internDeduplicatesIdenticalLeafNodes() {
        let cache = NodeCache()

        let node1 = Node(kind: .identifier, text: "ext")
        let node2 = Node(kind: .identifier, text: "ext")

        let interned1 = cache.intern(node1)
        let interned2 = cache.intern(node2)

        #expect(interned1 === interned2, "Interning identical leaf nodes should return same instance")
    }
}

// MARK: - Demangling Integration Tests

@Suite(.serialized)
struct NodeCacheDemangleTests {

    @Test func demangleAsNodeDeduplicatesLeaves() throws {
        // Demangle the same symbol twice — leaf nodes should be shared
        // Note: must run serialized to avoid other tests clearing NodeCache.shared
        let node1 = try demangleAsNode("$sSiD")
        let node2 = try demangleAsNode("$sSiD")

        // Leaf nodes (e.g. .module("Swift")) should be the same instance
        let module1 = node1.first(of: .module)
        let module2 = node2.first(of: .module)
        #expect(module1 != nil)
        #expect(module1 === module2, "Same leaf nodes should be deduplicated via NodeCache.shared")
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

    @Test func interningDeduplicatesLeafNodesAcrossTrees() {
        let cache = NodeCache()

        // Create many trees with shared leaf structure
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

        // Intern all trees
        let interned = cache.intern(trees)

        // Tree roots are NOT cached, so they are different instances
        #expect(interned[0] !== interned[1], "Tree nodes with children are not cached")

        // But all leaf nodes should be shared across all trees
        // Every tree's deepest leaves (.module "Swift" and .identifier "Int") should be the same instance
        let leaf0a = interned[0].children[0].children[0].children[0] // .module "Swift"
        let leaf0b = interned[0].children[0].children[0].children[1] // .identifier "Int"
        for i in 1..<interned.count {
            let leafA = interned[i].children[0].children[0].children[0]
            let leafB = interned[i].children[0].children[0].children[1]
            #expect(leaf0a === leafA, "Leaf .module nodes should be deduplicated")
            #expect(leaf0b === leafB, "Leaf .identifier nodes should be deduplicated")
        }

        // Cache should only have 2 unique leaf nodes (module "Swift", identifier "Int")
        #expect(cache.count == 2, "Should have exactly 2 unique leaf nodes")
    }
}
