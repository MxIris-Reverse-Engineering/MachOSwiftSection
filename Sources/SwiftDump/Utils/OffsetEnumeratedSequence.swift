import Foundation

package struct OffsetEnumeratedSequence<Base: Collection>: Sequence {
    package struct OffsetInfo {
        package let index: Int
        package let isStart: Bool
        package let isEnd: Bool

        fileprivate init(index: Int, isStart: Bool, isEnd: Bool) {
            self.index = index
            self.isStart = isStart
            self.isEnd = isEnd
        }
    }

    package typealias Element = (offset: OffsetInfo, element: Base.Element)

    package typealias Iterator = TargetIterator<Base.Iterator>
    
    package struct TargetIterator<BaseIterator: IteratorProtocol>: IteratorProtocol {
        package typealias Element = (offset: OffsetInfo, element: BaseIterator.Element)

        private var baseIterator: BaseIterator
        private var currentIndex: Int
        private let totalCount: Int

        fileprivate init(baseIterator: BaseIterator, count: Int) {
            self.baseIterator = baseIterator
            self.currentIndex = 0
            self.totalCount = count
        }

        package mutating func next() -> Element? {
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

    package func makeIterator() -> Iterator {
        return Iterator(baseIterator: base.makeIterator(), count: base.count)
    }
}

extension Collection {
    package func offsetEnumerated() -> OffsetEnumeratedSequence<Self> {
        return OffsetEnumeratedSequence(self)
    }
}

extension OffsetEnumeratedSequence.OffsetInfo: CustomStringConvertible {
    package var description: String {
        var parts = ["index: \(index)"]
        if isStart { parts.append("isStart") }
        if isEnd { parts.append("isEnd") }
        return "Offset(\(parts.joined(separator: ", ")))"
    }
}
