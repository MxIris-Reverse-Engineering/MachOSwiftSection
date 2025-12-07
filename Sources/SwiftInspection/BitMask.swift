import Foundation

public struct BitMask: Equatable, CustomStringConvertible {
    private var bytes: [UInt8]

    public var size: Int {
        return bytes.count
    }

    public var numBits: Int {
        return size * 8
    }

    // MARK: - Initializers

    public init(sizeInBytes: Int) {
        self.bytes = [UInt8](repeating: 0xFF, count: sizeInBytes)
    }

    public init(sizeInBytes: Int, sourceMask: UInt64) {
        self.bytes = [UInt8](repeating: 0, count: sizeInBytes)
        withUnsafeBytes(of: sourceMask) { buffer in
            let copyCount = min(sizeInBytes, buffer.count)
            for i in 0 ..< copyCount {
                self.bytes[i] = buffer[i]
            }
        }
    }

    public init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    public static let arm64SpareBitsMask: UInt64 = 0xF000000000000007
    
    // MARK: - Static Factories

    public static func zeroMask(sizeInBytes: Int) -> BitMask {
        var mask = BitMask(sizeInBytes: sizeInBytes)
        mask.makeZero()
        return mask
    }

    public static func oneMask(sizeInBytes: Int) -> BitMask {
        return BitMask(sizeInBytes: sizeInBytes)
    }

    // MARK: - Basic Operations

    public mutating func makeZero() {
        for i in 0 ..< bytes.count {
            bytes[i] = 0
        }
    }

    public var isZero: Bool {
        return !bytes.contains { $0 != 0 }
    }

    public var isNonZero: Bool {
        return !isZero
    }

    public mutating func complement() {
        for i in 0 ..< bytes.count {
            bytes[i] = ~bytes[i]
        }
    }

    public var numSetBits: Int {
        // Hamming weight
        var count = 0
        for byte in bytes {
            count += byte.nonzeroBitCount
        }
        return count
    }

    public var numZeroBits: Int {
        return (size * 8) - numSetBits
    }

    // MARK: - Masking Operations

    public mutating func andMask(_ other: BitMask, offset: Int) {
        guard offset < size else { return }

        let commonLen = min(other.size, size - offset)
        for i in 0 ..< commonLen {
            bytes[i + offset] &= other.bytes[i]
        }
    }

    public mutating func andNotMask(_ other: BitMask, offset: Int) {
        guard offset < size else { return }

        let commonLen = min(other.size, size - offset)
        for i in 0 ..< commonLen {
            bytes[i + offset] &= ~other.bytes[i]
        }
    }

    // MARK: - Truncation Operations

    public mutating func keepOnlyMostSignificantBits(_ n: Int) {
        guard size > 0 else { return }

        var count = 0
        var i = size
        while i > 0 {
            i -= 1
            if count < n {
                var b: UInt8 = 128 // 0x80
                while b > 0 {
                    if count >= n {
                        bytes[i] &= ~b
                    } else if (bytes[i] & b) != 0 {
                        count += 1
                    }
                    b >>= 1
                }
            } else {
                bytes[i] = 0
            }
        }
    }

    public mutating func keepOnlyLeastSignificantBytes(_ n: Int) {
        if size > n {
            bytes = Array(bytes.prefix(n))
        }
    }

    // MARK: - Reading Values

    public func readMaskedInteger(from data: [UInt8], offset: Int = 0) -> UInt64? {
        guard data.count >= offset + size else { return nil }

        var result: UInt64 = 0
        var resultBit: UInt64 = 1

        for i in 0 ..< size {
            let maskByte = bytes[i]
            let dataByte = data[offset + i]

            var b: UInt8 = 1
            while b != 0 {
                if (maskByte & b) != 0 {
                    if (dataByte & b) != 0 {
                        result |= resultBit
                    }

                    resultBit <<= 1
                }
                b = b &<< 1
            }
        }

        return result
    }

    // MARK: - Debugging

    public var description: String {
        var str = "\(size):0x"
        for byte in bytes {
            str += String(format: "%02x", byte)
        }
        return str
    }
}
