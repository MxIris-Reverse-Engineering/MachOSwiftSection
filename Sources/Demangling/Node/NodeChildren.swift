/// Compact inline storage for Node children.
///
/// Stores 0–2 children inline without heap allocation, which covers ~80% of
/// demangled-tree nodes. Falls back to `ContiguousArray` for 3+ children.
///
/// Memory savings vs `[Node]`:
///   - 0 children: same (no heap allocation either way)
///   - 1 child: saves ~48 bytes heap (array buffer header)
///   - 2 children: saves ~48 bytes heap
///   - 3+ children: identical (heap-backed)
public struct NodeChildren: Sendable {
    @usableFromInline
    enum Storage: Sendable {
        case zero
        case one(Node)
        case two(Node, Node)
        case many(ContiguousArray<Node>)
    }

    @usableFromInline
    var storage: Storage

    @inlinable
    public init() {
        storage = .zero
    }

    @inlinable
    init(_ child: Node) {
        storage = .one(child)
    }

    @inlinable
    init(_ child0: Node, _ child1: Node) {
        storage = .two(child0, child1)
    }

    @inlinable
    public init(_ children: [Node]) {
        switch children.count {
        case 0: storage = .zero
        case 1: storage = .one(children[0])
        case 2: storage = .two(children[0], children[1])
        default: storage = .many(ContiguousArray(children))
        }
    }

    @inlinable
    init(_ children: ContiguousArray<Node>) {
        switch children.count {
        case 0: storage = .zero
        case 1: storage = .one(children[0])
        case 2: storage = .two(children[0], children[1])
        default: storage = .many(children)
        }
    }
}

// MARK: - RandomAccessCollection

extension NodeChildren: RandomAccessCollection, MutableCollection {
    public typealias Index = Int
    public typealias Element = Node

    @inlinable
    public var startIndex: Int { 0 }

    @inlinable
    public var endIndex: Int {
        switch storage {
        case .zero: return 0
        case .one: return 1
        case .two: return 2
        case .many(let arr): return arr.count
        }
    }

    @inlinable
    public var count: Int { endIndex }

    @inlinable
    public var isEmpty: Bool {
        if case .zero = storage { return true }
        return false
    }

    @inlinable
    public subscript(index: Int) -> Node {
        get {
            switch storage {
            case .zero:
                fatalError("Index \(index) out of range for empty NodeChildren")
            case .one(let n):
                guard index == 0 else {
                    fatalError("Index \(index) out of range for NodeChildren with 1 element")
                }
                return n
            case .two(let n0, let n1):
                switch index {
                case 0: return n0
                case 1: return n1
                default:
                    fatalError("Index \(index) out of range for NodeChildren with 2 elements")
                }
            case .many(let arr):
                return arr[index]
            }
        }
        set {
            switch storage {
            case .zero:
                fatalError("Index \(index) out of range for empty NodeChildren")
            case .one:
                guard index == 0 else {
                    fatalError("Index \(index) out of range for NodeChildren with 1 element")
                }
                storage = .one(newValue)
            case .two(let n0, let n1):
                switch index {
                case 0: storage = .two(newValue, n1)
                case 1: storage = .two(n0, newValue)
                default:
                    fatalError("Index \(index) out of range for NodeChildren with 2 elements")
                }
            case .many(var arr):
                arr[index] = newValue
                storage = .many(arr)
            }
        }
    }
}

// MARK: - Mutation Methods

extension NodeChildren {
    @inlinable
    mutating func append(_ element: Node) {
        switch storage {
        case .zero:
            storage = .one(element)
        case .one(let n):
            storage = .two(n, element)
        case .two(let n0, let n1):
            storage = .many(ContiguousArray([n0, n1, element]))
        case .many(var arr):
            arr.append(element)
            storage = .many(arr)
        }
    }

    @inlinable
    mutating func append(contentsOf elements: some Collection<Node>) {
        switch (storage, elements.count) {
        case (_, 0):
            return
        case (.zero, 1):
            storage = .one(elements.first!)
        case (.zero, 2):
            let iter = elements.makeIterator()
            var iter2 = iter
            let a = iter2.next()!
            let b = iter2.next()!
            storage = .two(a, b)
        case (.one(let n), 1):
            storage = .two(n, elements.first!)
        default:
            var arr = toContiguousArray()
            arr.append(contentsOf: elements)
            storage = .many(arr)
        }
    }

    @inlinable
    mutating func insert(_ element: Node, at index: Int) {
        switch storage {
        case .zero:
            guard index == 0 else { return }
            storage = .one(element)
        case .one(let n):
            switch index {
            case 0: storage = .two(element, n)
            case 1: storage = .two(n, element)
            default: return
            }
        case .two(let n0, let n1):
            var arr = ContiguousArray([n0, n1])
            arr.insert(element, at: index)
            storage = .many(arr)
        case .many(var arr):
            arr.insert(element, at: index)
            storage = .many(arr)
        }
    }

    @inlinable
    @discardableResult
    mutating func remove(at index: Int) -> Node {
        switch storage {
        case .zero:
            fatalError("Index out of range")
        case .one(let n):
            guard index == 0 else { fatalError("Index out of range") }
            storage = .zero
            return n
        case .two(let n0, let n1):
            switch index {
            case 0:
                storage = .one(n1)
                return n0
            case 1:
                storage = .one(n0)
                return n1
            default:
                fatalError("Index out of range")
            }
        case .many(var arr):
            let removed = arr.remove(at: index)
            // Compact back to inline if possible
            switch arr.count {
            case 0: storage = .zero
            case 1: storage = .one(arr[0])
            case 2: storage = .two(arr[0], arr[1])
            default: storage = .many(arr)
            }
            return removed
        }
    }

    @inlinable
    mutating func reverse() {
        switch storage {
        case .zero, .one:
            break
        case .two(let n0, let n1):
            storage = .two(n1, n0)
        case .many(var arr):
            arr.reverse()
            storage = .many(arr)
        }
    }

    @inlinable
    mutating func reverseFirst(_ count: Int) {
        guard count > 1 else { return }
        switch storage {
        case .zero, .one:
            break
        case .two(let n0, let n1):
            if count >= 2 {
                storage = .two(n1, n0)
            }
        case .many(var arr):
            guard count <= arr.count else { return }
            let endIndex = count - 1
            for i in 0 ..< (count / 2) {
                arr.swapAt(i, endIndex - i)
            }
            storage = .many(arr)
        }
    }
}

// MARK: - Conversion

extension NodeChildren {
    @inlinable
    func toContiguousArray() -> ContiguousArray<Node> {
        switch storage {
        case .zero: return []
        case .one(let n): return [n]
        case .two(let n0, let n1): return [n0, n1]
        case .many(let arr): return arr
        }
    }

    @inlinable
    public func toArray() -> [Node] {
        switch storage {
        case .zero: return []
        case .one(let n): return [n]
        case .two(let n0, let n1): return [n0, n1]
        case .many(let arr): return Array(arr)
        }
    }
}

// MARK: - Concatenation Operators

extension NodeChildren {
    @inlinable
    static func + (lhs: NodeChildren, rhs: [Node]) -> NodeChildren {
        if rhs.isEmpty { return lhs }
        var result = lhs
        result.append(contentsOf: rhs)
        return result
    }

    @inlinable
    static func + (lhs: NodeChildren, rhs: NodeChildren) -> NodeChildren {
        if rhs.isEmpty { return lhs }
        if lhs.isEmpty { return rhs }
        var arr = lhs.toContiguousArray()
        arr.append(contentsOf: rhs)
        return NodeChildren(arr)
    }
}

// MARK: - Safe Access (mirrors Array extensions in Extensions.swift)

extension NodeChildren {
    @inlinable
    public func at(_ index: Int) -> Node? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }

    @inlinable
    public subscript(safe index: Int) -> Node? {
        at(index)
    }

    @inlinable
    public var second: Node? {
        at(1)
    }

    @inlinable
    public func reversedFirst(_ count: Int) -> NodeChildren {
        var result = self
        result.reverseFirst(count)
        return result
    }

    @inlinable
    public func slice(_ from: Int, _ to: Int) -> ArraySlice<Node> {
        let arr = toArray()
        if from > to || from > arr.endIndex || to < arr.startIndex {
            return ArraySlice()
        } else {
            return arr[(from > arr.startIndex ? from : arr.startIndex) ..< (to < arr.endIndex ? to : arr.endIndex)]
        }
    }
}

// MARK: - Equatable

extension NodeChildren: Equatable {
    @inlinable
    public static func == (lhs: NodeChildren, rhs: NodeChildren) -> Bool {
        guard lhs.count == rhs.count else { return false }
        switch (lhs.storage, rhs.storage) {
        case (.zero, .zero):
            return true
        case (.one(let l), .one(let r)):
            return l == r
        case (.two(let l0, let l1), .two(let r0, let r1)):
            return l0 == r0 && l1 == r1
        default:
            // General case: element-wise comparison
            for i in 0 ..< lhs.count {
                if lhs[i] != rhs[i] { return false }
            }
            return true
        }
    }
}

// MARK: - Hashable

extension NodeChildren: Hashable {
    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        for child in self {
            hasher.combine(child)
        }
    }
}
