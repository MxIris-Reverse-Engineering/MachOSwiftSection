import Foundation

/// A Swift port of `Bitmask.h` from the Swift compiler.
/// Handles arbitrary-length bitmasks used for tracking spare bits in enum layouts.
public struct BitMask: Equatable, CustomStringConvertible, Sendable {
    private var _bytes: [UInt8]

    public var size: Int { _bytes.count }

    /// Read-only access to raw bytes.
    public var bytes: [UInt8] { _bytes }

    // MARK: - Initializers

    /// Construct a bitmask of the appropriate number of bytes, initialized to all bits set (1).
    public init(sizeInBytes: Int) {
        self._bytes = [UInt8](repeating: 0xFF, count: sizeInBytes)
    }

    /// Construct from raw bytes.
    public init(bytes: [UInt8]) {
        self._bytes = bytes
    }

    /// Construct a zero mask.
    public static func zeroMask(sizeInBytes: Int) -> BitMask {
        var mask = BitMask(sizeInBytes: sizeInBytes)
        mask.makeZero()
        return mask
    }

    // MARK: - Accessors

    /// Safe read/write access to bytes.
    public subscript(byteAt index: Int) -> UInt8 {
        get {
            guard index < _bytes.count else { return 0 }
            return _bytes[index]
        }
        set {
            if index < _bytes.count {
                _bytes[index] = newValue
            }
        }
    }

    // MARK: - Manipulation

    public mutating func makeZero() {
        for i in 0 ..< _bytes.count {
            _bytes[i] = 0
        }
    }

    public mutating func invert() {
        for i in 0 ..< _bytes.count {
            _bytes[i] = ~_bytes[i]
        }
    }

    /// Subtracts another mask from this one (self = self & ~other).
    /// Used to calculate remaining spare bits after tag bits are selected.
    public mutating func formSubtract(_ other: BitMask) {
        let count = min(size, other.size)
        for i in 0 ..< count {
            _bytes[i] &= ~other._bytes[i]
        }
    }

    /// Zero all bits except for the `n` most significant ones.
    /// Scans from High Address -> Low Address, High Bit -> Low Bit.
    /// This is the core logic for selecting Tag bits in MPEs.
    public mutating func keepOnlyMostSignificantBits(_ n: Int) {
        guard size > 0 else { return }

        var count = 0
        var i = size

        while i > 0 {
            i -= 1
            if count < n {
                var b: UInt8 = 128 // Bit 7
                while b > 0 {
                    if count >= n {
                        _bytes[i] &= ~b
                    } else if (_bytes[i] & b) != 0 {
                        count += 1
                    }
                    b >>= 1
                }
            } else {
                _bytes[i] = 0
            }
        }
    }

    // MARK: - Queries

    public var isZero: Bool {
        return !_bytes.contains { $0 != 0 }
    }

    public func countSetBits() -> Int {
        return _bytes.reduce(0) { $0 + $1.nonzeroBitCount }
    }

    // MARK: - Scatter (PDEP)

    /// Unpack bits from the low bits of `value` and move them to the bit positions
    /// indicated by this mask. (Used for writing Tags/PayloadValues)
    /// Corresponds to `irgen::emitScatterBits` / `APInt::scatterBits`.
    public func scatterBits(value: Int) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: size)
        var tempValue = value

        // Iterate from LSB (Byte 0, Bit 0) to MSB
        for i in 0 ..< size {
            let maskByte = _bytes[i]
            if maskByte == 0 { continue }

            var b: UInt8 = 1
            while b != 0 {
                if (maskByte & b) != 0 {
                    // If mask has a bit, take the next bit from value
                    if (tempValue & 1) == 1 {
                        result[i] |= b
                    }
                    tempValue >>= 1
                }
                if b == 128 { break }
                b <<= 1
            }
        }
        return result
    }

    public var description: String {
        return _bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
