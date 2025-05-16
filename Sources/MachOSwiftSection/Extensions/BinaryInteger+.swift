import Foundation
import MachOKit

extension BinaryInteger {
    func cast<T: BinaryInteger>() -> T {
        numericCast(self)
    }
}

extension BinaryInteger {
    mutating func offset<T>(of type: T.Type, numbersOfElements: Int = 1) {
        self += numericCast(MemoryLayout<T>.size * numbersOfElements)
    }

    mutating func offset<T: LayoutWrapper>(of type: T.Type, numbersOfElements: Int = 1) {
        self += numericCast(MemoryLayout<T.Layout>.size * numbersOfElements)
    }

    func offseting<T>(of type: T.Type, numbersOfElements: Int = 1) -> Self {
        return self * numericCast(MemoryLayout<T>.size * numbersOfElements)
    }
}
