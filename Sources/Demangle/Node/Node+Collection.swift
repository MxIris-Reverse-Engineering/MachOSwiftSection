// MARK: - Collection Support

extension Node {
    // MARK: - Traversal Methods

    public func preorder() -> PreorderSequence {
        PreorderSequence(root: self)
    }

    public func inorder() -> InorderSequence {
        InorderSequence(root: self)
    }

    public func postorder() -> PostorderSequence {
        PostorderSequence(root: self)
    }

    public func levelorder() -> LevelorderSequence {
        LevelorderSequence(root: self)
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
