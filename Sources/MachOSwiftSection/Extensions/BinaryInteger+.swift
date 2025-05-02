import Foundation

extension BinaryInteger {
    func cast<T: BinaryInteger>() -> T {
        numericCast(self)
    }
}
