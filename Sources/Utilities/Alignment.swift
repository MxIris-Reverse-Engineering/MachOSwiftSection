import Foundation

extension FixedWidthInteger {
    /*@inlinable*/
//    @inline(__always)
    package func aligned(to alignment: Self) -> Self {
        assert(alignment > 0 && (alignment & (alignment - 1) == 0), "Alignment must be a power of 2")
        return (self &+ alignment &- 1) & ~(alignment &- 1)
    }

    /*@inlinable*/
//    @inline(__always)
    package mutating func align(to alignment: Self) {
        self = aligned(to: alignment)
    }
}
