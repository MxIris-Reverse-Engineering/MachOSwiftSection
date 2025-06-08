import Foundation

struct OffsetEnumeratedSequence<Base: Collection>: Sequence {
    struct OffsetInfo {
        let index: Int
        let isStart: Bool
        let isEnd: Bool

        init(index: Int, isStart: Bool, isEnd: Bool) {
            self.index = index
            self.isStart = isStart
            self.isEnd = isEnd
        }
    }

    typealias Element = (offset: OffsetInfo, element: Base.Element)

    typealias Iterator = TargetIterator<Base.Iterator>
    
    struct TargetIterator<BaseIterator: IteratorProtocol>: IteratorProtocol {
        typealias Element = (offset: OffsetInfo, element: BaseIterator.Element)

        private var baseIterator: BaseIterator
        private var currentIndex: Int
        private let totalCount: Int

        init(baseIterator: BaseIterator, count: Int) {
            self.baseIterator = baseIterator
            self.currentIndex = 0
            self.totalCount = count
        }

        mutating func next() -> Element? {
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

    init(_ base: Base) {
        self.base = base
    }

    func makeIterator() -> Iterator {
        return Iterator(baseIterator: base.makeIterator(), count: base.count)
    }
}

extension Collection {
    func offsetEnumerated() -> OffsetEnumeratedSequence<Self> {
        return OffsetEnumeratedSequence(self)
    }
}

extension OffsetEnumeratedSequence.OffsetInfo: CustomStringConvertible {
    var description: String {
        var parts = ["index: \(index)"]
        if isStart { parts.append("isStart") }
        if isEnd { parts.append("isEnd") }
        return "Offset(\(parts.joined(separator: ", ")))"
    }
}
