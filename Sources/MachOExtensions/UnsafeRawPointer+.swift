import Foundation

extension UnsafeRawPointer {
    package var uint: UInt {
        UInt(bitPattern: self)
    }
    
    package var int: Int {
        Int(bitPattern: self)
    }
}
