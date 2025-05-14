import Foundation

struct DataSequence<T>: Sequence {
    typealias Element = T

    private let data: Data
    private let entrySize: Int
    private let numberOfElements: Int

    init(
        data: Data,
        numberOfElements: Int
    ) {
        self.data = data
        self.entrySize = MemoryLayout<Element>.size
        self.numberOfElements = numberOfElements
    }

    init(
        data: Data,
        entrySize: Int
    ) {
        self.data = data
        self.entrySize = entrySize
        self.numberOfElements = data.count / entrySize
    }

    func makeIterator() -> Iterator {
        Iterator(
            data: data,
            entrySize: entrySize,
            numberOfElements: numberOfElements
        )
    }
}

extension DataSequence {
    struct Iterator: IteratorProtocol {
        typealias Element = T

        private let data: Data
        private let entrySize: Int
        private let numberOfElements: Int

        private var nextIndex: Int = 0
        private var nextOffset: Int = 0

        init(
            data: Data,
            entrySize: Int,
            numberOfElements: Int
        ) {
            self.data = data
            self.entrySize = entrySize
            self.numberOfElements = numberOfElements
        }

        mutating func next() -> Element? {
            guard nextIndex < numberOfElements else { return nil }
            guard nextOffset + entrySize <= data.count else { return nil }

            defer {
                nextIndex += 1
                nextOffset += entrySize
            }

            return data.withUnsafeBytes {
                guard let baseAddress = $0.baseAddress else { return nil }
                return baseAddress.advanced(by: nextOffset).load(as: Element.self)
            }
        }
    }
}

extension DataSequence: Collection {
    typealias Index = Int

    var startIndex: Index { 0 }
    var endIndex: Index { numberOfElements }

    func index(after i: Int) -> Int {
        i + 1
    }

    subscript(position: Int) -> Element {
        precondition(position >= 0)
        precondition(position < endIndex)
        precondition(data.count >= (position + 1) * entrySize)
        return data.withUnsafeBytes {
            guard let baseAddress = $0.baseAddress else {
                fatalError("data is empty")
            }
            return baseAddress
                .advanced(by: position * entrySize)
                .load(as: Element.self)
        }
    }
}

extension DataSequence: RandomAccessCollection {}
