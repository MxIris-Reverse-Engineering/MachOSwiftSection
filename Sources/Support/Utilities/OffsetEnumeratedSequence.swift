import Foundation

public struct OffsetEnumeratedSequence<Base: Collection>: Sequence {
    public struct OffsetInfo {
        public let index: Int
        public let isStart: Bool
        public let isEnd: Bool

        fileprivate init(index: Int, isStart: Bool, isEnd: Bool) {
            self.index = index
            self.isStart = isStart
            self.isEnd = isEnd
        }
    }

    public typealias Element = (offset: OffsetInfo, element: Base.Element)

    public typealias Iterator = TargetIterator<Base.Iterator>

    public struct TargetIterator<BaseIterator: IteratorProtocol>: IteratorProtocol {
        public typealias Element = (offset: OffsetInfo, element: BaseIterator.Element)

        private var baseIterator: BaseIterator
        private var currentIndex: Int
        private let totalCount: Int

        fileprivate init(baseIterator: BaseIterator, count: Int) {
            self.baseIterator = baseIterator
            self.currentIndex = 0
            self.totalCount = count
        }

        public mutating func next() -> Element? {
            guard let element = baseIterator.next() else {
                return nil
            }

            if totalCount == 0 {
                return nil
            }

            let isFirstElement = (currentIndex == 0)
            let isLastElement = (currentIndex == totalCount - 1)

            let offset = OffsetInfo(
                index: currentIndex,
                isStart: isFirstElement,
                isEnd: isLastElement
            )

            let result = (offset: offset, element: element)
            currentIndex += 1
            return result
        }
    }

    private let base: Base

    fileprivate init(_ base: Base) {
        self.base = base
    }

    public func makeIterator() -> Iterator {
        return Iterator(baseIterator: base.makeIterator(), count: base.count)
    }
}

extension Collection {
    public func offsetEnumerated() -> OffsetEnumeratedSequence<Self> {
        return OffsetEnumeratedSequence(self)
    }
}

extension OffsetEnumeratedSequence.OffsetInfo: CustomStringConvertible {
    public var description: String {
        var parts = ["index: \(index)"]
        if isStart { parts.append("isStart") }
        if isEnd { parts.append("isEnd") }
        return "Offset(\(parts.joined(separator: ", ")))"
    }
}
