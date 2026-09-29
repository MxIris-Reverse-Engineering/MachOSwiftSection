package struct MemorySequence<T>: Sequence {
    public typealias Element = T

    private let basePointer: UnsafeRawPointer
    private let entrySize: Int
    private let numberOfElements: Int

    package init(
        basePointer: UnsafePointer<T>,
        numberOfElements: Int
    ) {
        self.basePointer = .init(basePointer)
        self.entrySize = MemoryLayout<Element>.size
        self.numberOfElements = numberOfElements
    }

    package init(
        basePointer: UnsafePointer<T>,
        entrySize: Int,
        numberOfElements: Int
    ) {
        self.basePointer = .init(basePointer)
        self.entrySize = entrySize
        self.numberOfElements = numberOfElements
    }

    package func makeIterator() -> Iterator {
        Iterator(
            basePointer: basePointer,
            entrySize: entrySize,
            numberOfElements: numberOfElements
        )
    }
}

extension MemorySequence {
    package struct Iterator: IteratorProtocol {
        public typealias Element = T

        private let basePointer: UnsafeRawPointer
        private let entrySize: Int
        private let numberOfElements: Int

        private var nextIndex: Int = 0

        init(
            basePointer: UnsafeRawPointer,
            entrySize: Int,
            numberOfElements: Int
        ) {
            self.basePointer = basePointer
            self.entrySize = entrySize
            self.numberOfElements = numberOfElements
        }

        public mutating func next() -> Element? {
            guard nextIndex < numberOfElements else { return nil }
            defer { nextIndex += 1 }
            return basePointer
                .advanced(by: nextIndex * entrySize)
                .load(as: Element.self)
        }
    }
}

extension MemorySequence: Collection {
    package typealias Index = Int

    package var startIndex: Index { 0 }
    package var endIndex: Index { numberOfElements }

    package func index(after i: Int) -> Int {
        i + 1
    }

    package subscript(position: Int) -> Element {
        precondition(position >= 0)
        precondition(position < endIndex)
        return basePointer
            .advanced(by: position * entrySize)
            .load(as: Element.self)
    }
}

extension MemorySequence: RandomAccessCollection {}
