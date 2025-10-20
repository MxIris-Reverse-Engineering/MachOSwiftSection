extension Node {
    public func preorder() -> some Sequence<Node> {
        PreorderSequence(root: self)
    }

    public func inorder() -> some Sequence<Node> {
        InorderSequence(root: self)
    }

    public func postorder() -> some Sequence<Node> {
        PostorderSequence(root: self)
    }

    public func levelorder() -> some Sequence<Node> {
        LevelorderSequence(root: self)
    }

    private struct PreorderSequence: Sequence {
        struct Iterator: IteratorProtocol {
            private var stack: [Node]

            fileprivate init(root: Node) {
                self.stack = [root]
            }

            mutating func next() -> Node? {
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

        func makeIterator() -> Iterator {
            Iterator(root: root)
        }
    }

    private struct InorderSequence: Sequence {
        struct Iterator: IteratorProtocol {
            private var stack: [Node]
            private var current: Node?

            fileprivate init(root: Node) {
                self.stack = []
                self.current = root
            }

            mutating func next() -> Node? {
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

        func makeIterator() -> Iterator {
            Iterator(root: root)
        }
    }

    private struct PostorderSequence: Sequence {
        public struct Iterator: IteratorProtocol {
            private var stack: [(node: Node, visited: Bool)]

            fileprivate init(root: Node) {
                self.stack = [(root, false)]
            }

            mutating func next() -> Node? {
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

        func makeIterator() -> Iterator {
            Iterator(root: root)
        }
    }

    private struct LevelorderSequence: Sequence {
        struct Iterator: IteratorProtocol {
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

        func makeIterator() -> Iterator {
            Iterator(root: root)
        }
    }
}

extension Node: Sequence {
    public typealias Element = Node

    public func makeIterator() -> some IteratorProtocol<Node> {
        preorder().makeIterator()
    }
}

extension Sequence where Element == Node {
    public func first(of kind: Node.Kind) -> Node? {
        first { $0.kind == kind }
    }

    public func first(of kinds: Node.Kind...) -> Node? {
        first { kinds.contains($0.kind) }
    }

    public func contains(_ kind: Node.Kind) -> Bool {
        contains { $0.kind == kind }
    }

    public func contains(_ kinds: Node.Kind...) -> Bool {
        contains { kinds.contains($0.kind) }
    }

    public func all(of kind: Node.Kind) -> [Node] {
        filter { $0.kind == kind }
    }

    public func all(of kinds: Node.Kind...) -> [Node] {
        filter { kinds.contains($0.kind) }
    }

    public func all(of kinds: [Node.Kind]) -> [Node] {
        filter { kinds.contains($0.kind) }
    }
    
    public func filter(of kind: Node.Kind) -> some Sequence<Node> {
        filter { $0.kind == kind }
    }

    public func filter(of kinds: Node.Kind...) -> some Sequence<Node> {
        filter { kinds.contains($0.kind) }
    }
}
