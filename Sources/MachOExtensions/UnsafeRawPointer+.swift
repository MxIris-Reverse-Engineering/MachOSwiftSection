import Foundation
import MachOKit

extension UnsafeRawPointer {
    package var uint: UInt {
        UInt(bitPattern: self)
    }

    package var int: Int {
        Int(bitPattern: self)
    }
}

extension UnsafeRawPointer {
    @usableFromInline
    package enum Error: Swift.Error {
        case initFailed
    }

    @inlinable
    package init(bitPattern: UInt) throws {
        if let ptr = UnsafeRawPointer(bitPattern: bitPattern) {
            self = ptr
        } else {
            throw Error.initFailed
        }
    }

    @inlinable
    package init(bitPattern: Int) throws {
        if let ptr = UnsafeRawPointer(bitPattern: bitPattern) {
            self = ptr
        } else {
            throw Error.initFailed
        }
    }
}

extension UnsafeRawPointer {
    package mutating func offset<T>(of type: T.Type, numbersOfElements: Int = 1) {
        self += numericCast(MemoryLayout<T>.size * numbersOfElements)
    }

    package mutating func offset<T: LayoutWrapper>(of type: T.Type, numbersOfElements: Int = 1) {
        self += numericCast(T.layoutSize * numbersOfElements)
    }

    package func offseting<T>(of type: T.Type, numbersOfElements: Int = 1) -> Self {
        return self + numericCast(MemoryLayout<T>.size * numbersOfElements)
    }

    package func offseting<T: LayoutWrapper>(of type: T.Type, numbersOfElements: Int = 1) -> Self {
        return self + numericCast(T.layoutSize * numbersOfElements)
    }
}
