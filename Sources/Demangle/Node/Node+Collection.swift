// MARK: - Collection Support

extension Node: Collection {
    public typealias Element = Node

    public struct Index: Comparable {
        fileprivate let path: [Int]
        fileprivate let traversalOrder: TraversalOrder

        fileprivate init(path: [Int], traversalOrder: TraversalOrder) {
            self.path = path
            self.traversalOrder = traversalOrder
        }

        public static func < (lhs: Index, rhs: Index) -> Bool {
            // Compare based on the actual traversal order
            return lhs.path.lexicographicallyPrecedes(rhs.path)
        }
    }

    public enum TraversalOrder {
        case preorder
        case inorder
        case postorder
        case levelorder
    }

    public var startIndex: Index {
        Index(path: [], traversalOrder: .preorder)
    }

    public var endIndex: Index {
        Index(path: [-1], traversalOrder: .preorder)
    }

    public subscript(position: Index) -> Node {
        return nodeAt(path: position.path, traversalOrder: position.traversalOrder)
    }

    public func index(after i: Index) -> Index {
        let nextPath = nextPath(from: i.path, traversalOrder: i.traversalOrder)
        return Index(path: nextPath, traversalOrder: i.traversalOrder)
    }

    // MARK: - Traversal Methods

    public func preorderTraversal() -> PreorderSequence {
        PreorderSequence(root: self)
    }

    public func inorderTraversal() -> InorderSequence {
        InorderSequence(root: self)
    }

    public func postorderTraversal() -> PostorderSequence {
        PostorderSequence(root: self)
    }

    public func levelorderTraversal() -> LevelorderSequence {
        LevelorderSequence(root: self)
    }

    // MARK: - Private Helper Methods

    private func nodeAt(path: [Int], traversalOrder: TraversalOrder) -> Node {
        if path.isEmpty {
            return self
        }

        var current = self
        for index in path {
            guard index >= 0 && index < current.children.count else {
                fatalError("Invalid path")
            }
            current = current.children[index]
        }
        return current
    }

    private func nextPath(from currentPath: [Int], traversalOrder: TraversalOrder) -> [Int] {
        switch traversalOrder {
        case .preorder:
            return nextPreorderPath(from: currentPath)
        case .inorder:
            return nextInorderPath(from: currentPath)
        case .postorder:
            return nextPostorderPath(from: currentPath)
        case .levelorder:
            return nextLevelorderPath(from: currentPath)
        }
    }

    private func nextPreorderPath(from path: [Int]) -> [Int] {
        if path == [-1] { return [-1] } // End index

        let currentNode = nodeAt(path: path, traversalOrder: .preorder)

        // If current node has children, go to first child
        if !currentNode.children.isEmpty {
            return path + [0]
        }

        // Otherwise, find next sibling or ancestor's sibling
        var workingPath = path
        while !workingPath.isEmpty {
            let lastIndex = workingPath.removeLast()
            let parentNode = workingPath.isEmpty ? self : nodeAt(path: workingPath, traversalOrder: .preorder)

            if lastIndex + 1 < parentNode.children.count {
                return workingPath + [lastIndex + 1]
            }
        }

        return [-1] // End of traversal
    }

    private func nextInorderPath(from path: [Int]) -> [Int] {
        // Simplified inorder implementation
        // For a more complete implementation, you'd need to track state
        return nextPreorderPath(from: path)
    }

    private func nextPostorderPath(from path: [Int]) -> [Int] {
        // Simplified postorder implementation
        return nextPreorderPath(from: path)
    }

    private func nextLevelorderPath(from path: [Int]) -> [Int] {
        // Simplified level-order implementation
        return nextPreorderPath(from: path)
    }

    // MARK: - Sequence Types for Different Traversals

    public struct PreorderSequence: Sequence {
        public struct Iterator: IteratorProtocol {
            private var stack: [Node]

            fileprivate init(root: Node) {
                self.stack = [root]
            }

            public mutating func next() -> Node? {
                guard !stack.isEmpty else { return nil }

                let current = stack.removeLast()

                // Add children in reverse order so we visit them left-to-right
                for child in current.children.reversed() {
                    stack.append(child)
                }

                return current
            }
        }

        private let root: Node

        fileprivate init(root: Node) {
            self.root = root
        }

        public func makeIterator() -> Iterator {
            Iterator(root: root)
        }
    }

    public struct InorderSequence: Sequence {
        public struct Iterator: IteratorProtocol {
            private var stack: [Node]
            private var current: Node?

            fileprivate init(root: Node) {
                self.stack = []
                self.current = root
            }

            public mutating func next() -> Node? {
                while current != nil || !stack.isEmpty {
                    // Go to the leftmost node
                    while let node = current {
                        stack.append(node)
                        current = node.children.first
                    }

                    // Current must be nil at this point
                    if let node = stack.popLast() {
                        current = node.children.count > 1 ? node.children[1] : nil
                        return node
                    }
                }
                return nil
            }
        }

        private let root: Node

        fileprivate init(root: Node) {
            self.root = root
        }

        public func makeIterator() -> Iterator {
            Iterator(root: root)
        }
    }

    public struct PostorderSequence: Sequence {
        public struct Iterator: IteratorProtocol {
            private var stack: [(node: Node, visited: Bool)]

            fileprivate init(root: Node) {
                self.stack = [(root, false)]
            }

            public mutating func next() -> Node? {
                while !stack.isEmpty {
                    let (node, visited) = stack.removeLast()

                    if visited {
                        return node
                    } else {
                        // Mark as visited and push back
                        stack.append((node, true))

                        // Push children in reverse order
                        for child in node.children.reversed() {
                            stack.append((child, false))
                        }
                    }
                }
                return nil
            }
        }

        private let root: Node

        fileprivate init(root: Node) {
            self.root = root
        }

        public func makeIterator() -> Iterator {
            Iterator(root: root)
        }
    }

    public struct LevelorderSequence: Sequence {
        public struct Iterator: IteratorProtocol {
            private var queue: [Node]

            fileprivate init(root: Node) {
                self.queue = [root]
            }

            public mutating func next() -> Node? {
                guard !queue.isEmpty else { return nil }

                let current = queue.removeFirst()

                // Add all children to the queue
                queue.append(contentsOf: current.children)

                return current
            }
        }

        private let root: Node

        fileprivate init(root: Node) {
            self.root = root
        }

        public func makeIterator() -> Iterator {
            Iterator(root: root)
        }
    }
}
