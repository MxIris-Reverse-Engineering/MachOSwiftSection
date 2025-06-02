import Foundation
import MachOKit

extension BinaryInteger {
    package func cast<T: BinaryInteger>() -> T {
        numericCast(self)
    }
}

extension BinaryInteger {
    package mutating func offset<T>(of type: T.Type, numbersOfElements: Int = 1) {
        self += numericCast(MemoryLayout<T>.size * numbersOfElements)
    }

    package mutating func offset<T: LayoutWrapper>(of type: T.Type, numbersOfElements: Int = 1) {
        self += numericCast(T.layoutSize * numbersOfElements)
    }

    package func offseting<T>(of type: T.Type, numbersOfElements: Int = 1) -> Self {
        return self * numericCast(MemoryLayout<T>.size * numbersOfElements)
    }
    
    package func offseting<T: LayoutWrapper>(of type: T.Type, numbersOfElements: Int = 1) -> Self {
        return self * numericCast(T.layoutSize * numbersOfElements)
    }
}
