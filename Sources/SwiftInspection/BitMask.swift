// import Foundation
//
// public struct BitMask: Equatable, CustomStringConvertible {
//    public private(set) var bytes: [UInt8]
//
//    public var size: Int {
//        return bytes.count
//    }
//
//    public var numBits: Int {
//        return size * 8
//    }
//
//    // MARK: - Initializers
//
//    public init(sizeInBytes: Int) {
//        self.bytes = [UInt8](repeating: 0xFF, count: sizeInBytes)
//    }
//
//    public init(sizeInBytes: Int, sourceMask: UInt64) {
//        self.bytes = [UInt8](repeating: 0, count: sizeInBytes)
//        withUnsafeBytes(of: sourceMask) { buffer in
//            let copyCount = min(sizeInBytes, buffer.count)
//            for i in 0 ..< copyCount {
//                self.bytes[i] = buffer[i]
//            }
//        }
//    }
//
//    public init(bytes: [UInt8]) {
//        self.bytes = bytes
//    }
//
//    public static let arm64SpareBitsMask: UInt64 = 0xF000000000000007
//
//    // MARK: - Static Factories
//
//    public static func zeroMask(sizeInBytes: Int) -> BitMask {
//        var mask = BitMask(sizeInBytes: sizeInBytes)
//        mask.makeZero()
//        return mask
//    }
//
//    public static func oneMask(sizeInBytes: Int) -> BitMask {
//        return BitMask(sizeInBytes: sizeInBytes)
//    }
//
//    // MARK: - Basic Operations
//
//    public mutating func makeZero() {
//        for i in 0 ..< bytes.count {
//            bytes[i] = 0
//        }
//    }
//
//    public var isZero: Bool {
//        return !bytes.contains { $0 != 0 }
//    }
//
//    public var isNonZero: Bool {
//        return !isZero
//    }
//
//    public mutating func complement() {
//        for i in 0 ..< bytes.count {
//            bytes[i] = ~bytes[i]
//        }
//    }
//
//    public var numSetBits: Int {
//        // Hamming weight
//        var count = 0
//        for byte in bytes {
//            count += byte.nonzeroBitCount
//        }
//        return count
//    }
//
//    public var numZeroBits: Int {
//        return (size * 8) - numSetBits
//    }
//
//    // MARK: - Masking Operations
//
//    public mutating func andMask(_ other: BitMask, offset: Int) {
//        guard offset < size else { return }
//
//        let commonLen = min(other.size, size - offset)
//        for i in 0 ..< commonLen {
//            bytes[i + offset] &= other.bytes[i]
//        }
//    }
//
//    public mutating func andNotMask(_ other: BitMask, offset: Int) {
//        guard offset < size else { return }
//
//        let commonLen = min(other.size, size - offset)
//        for i in 0 ..< commonLen {
//            bytes[i + offset] &= ~other.bytes[i]
//        }
//    }
//
//    // MARK: - Truncation Operations
//
//    public mutating func keepOnlyMostSignificantBits(_ n: Int) {
//        guard size > 0 else { return }
//
//        var count = 0
//        var i = size
//        while i > 0 {
//            i -= 1
//            if count < n {
//                var b: UInt8 = 128 // 0x80
//                while b > 0 {
//                    if count >= n {
//                        bytes[i] &= ~b
//                    } else if (bytes[i] & b) != 0 {
//                        count += 1
//                    }
//                    b >>= 1
//                }
//            } else {
//                bytes[i] = 0
//            }
//        }
//    }
//
//    public mutating func keepOnlyLeastSignificantBytes(_ n: Int) {
//        if size > n {
//            bytes = Array(bytes.prefix(n))
//        }
//    }
//
//    // MARK: - Reading Values
//
//    public func readMaskedInteger(from data: [UInt8], offset: Int = 0) -> UInt64? {
//        guard data.count >= offset + size else { return nil }
//
//        var result: UInt64 = 0
//        var resultBit: UInt64 = 1
//
//        for i in 0 ..< size {
//            let maskByte = bytes[i]
//            let dataByte = data[offset + i]
//
//            var b: UInt8 = 1
//            while b != 0 {
//                if (maskByte & b) != 0 {
//                    if (dataByte & b) != 0 {
//                        result |= resultBit
//                    }
//
//                    resultBit <<= 1
//                }
//                b = b &<< 1
//            }
//        }
//
//        return result
//    }
//
//    // MARK: - Debugging
//
//    public var description: String {
//        var str = "\(size):0x"
//        for byte in bytes {
//            str += String(format: "%02x", byte)
//        }
//        return str
//    }
//
//    public func analyze(startOffset: Int) {
//        print("=== Spare Bits Analysis (Little Endian Memory) ===")
//        print("Input Offset: \(startOffset)")
//        print("Input Bytes (Hex): \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
//        print("-------------------------------------------------------------")
//        print("Offset | Hex  | Binary (MSB->LSB) | Spare Bits (1=Spare)")
//        print("-------|------|-------------------|--------------------------")
//
//        var currentStartOffset: Int? = nil
//        var currentBitsCount = 0
//        var currentBytes: [UInt8] = []
//
//        for (index, byte) in bytes.enumerated() {
//            let absoluteOffset = startOffset + index
//            let hex = String(format: "%02X", byte)
//            let binary = toBinaryString(byte)
//
//            var interpretation = ""
//            if byte == 0 {
//                interpretation = "None (Used)"
//            } else if byte == 0xFF {
//                interpretation = "All 8 bits"
//            } else {
//                // 简单的位描述
//                var parts: [String] = []
//                if (byte & 0xF0) == 0xF0 { parts.append("High 4") }
//                if (byte & 0x0F) == 0x0F { parts.append("Low 4") }
//                if parts.isEmpty {
//                    var bits: [Int] = []
//                    for i in 0 ..< 8 {
//                        if (byte & (1 << i)) != 0 { bits.append(i) }
//                    }
//                    interpretation = "Bits: " + bits.map(String.init).joined(separator: ",")
//                } else {
//                    interpretation = parts.joined(separator: ", ")
//                }
//            }
//
//            print(String(format: "  +%02d  | 0x%@ |     %@      | %@", absoluteOffset, hex, binary, interpretation))
//
//            // 统计区域逻辑
//            if byte != 0 {
//                if currentStartOffset == nil {
//                    currentStartOffset = absoluteOffset
//                }
//                currentBitsCount += byte.nonzeroBitCount
//                currentBytes.append(byte)
//            } else {
//                if let start = currentStartOffset {
//                    let end = absoluteOffset
//                    printRegionSummary(range: start ..< end, bits: currentBitsCount, bytes: currentBytes)
//                    currentStartOffset = nil
//                    currentBitsCount = 0
//                    currentBytes = []
//                }
//            }
//        }
//
//        if let start = currentStartOffset {
//            let end = startOffset + bytes.count
//            printRegionSummary(range: start ..< end, bits: currentBitsCount, bytes: currentBytes)
//        }
//        print("=============================================================")
//    }
//
//    private func toBinaryString(_ byte: UInt8) -> String {
//        let binary = String(byte, radix: 2)
//        let padding = String(repeating: "0", count: 8 - binary.count)
//        return padding + binary
//    }
//
//    private func printRegionSummary(range: Range<Int>, bits: Int, bytes: [UInt8]) {
//        let maxTag: String
//        if bits >= 64 {
//            maxTag = "UInt64.max"
//        } else {
//            let val = (UInt64(1) << bits) - 1
//            let numberFormatter = NumberFormatter()
//            numberFormatter.numberStyle = .decimal
//            maxTag = numberFormatter.string(from: NSNumber(value: val)) ?? "\(val)"
//        }
//
//        print("------------------------------------------------------")
//        print(">>> Found Spare Region: Offset \(range)")
//        print(">>> Capacity: \(bits) bits (Max Tag: \(maxTag))")
//        print("------------------------------------------------------")
//    }
// }

// import Foundation

// public struct BitMask: Equatable, Sendable, CustomStringConvertible {
//
//    // 最大限制，防止恶意数据导致内存耗尽 (128MB)
//    private static let maxSize = 128 * 1024 * 1024
//
//    public private(set) var bytes: [UInt8]
//
//    public var size: Int {
//        return bytes.count
//    }
//
//    // MARK: - Initializers
//
//    /// 创建一个全 1 的掩码 (0xFF)
//    public init(sizeInBytes: Int) {
//        guard sizeInBytes > 0, sizeInBytes <= BitMask.maxSize else {
//            self.bytes = []
//            return
//        }
//        self.bytes = [UInt8](repeating: 0xFF, count: sizeInBytes)
//    }
//
//    /// 创建一个全 0 的掩码
//    public static func zero(sizeInBytes: Int) -> BitMask {
//        var mask = BitMask(sizeInBytes: sizeInBytes)
//        mask.makeZero()
//        return mask
//    }
//
//    public init(bytes: [UInt8]) {
//        self.bytes = bytes
//    }
//
//    /// 从 UInt64 创建掩码
//    public init(sizeInBytes: Int, sourceMask: UInt64) {
//        guard sizeInBytes > 0, sizeInBytes <= BitMask.maxSize else {
//            self.bytes = []
//            return
//        }
//        self.bytes = [UInt8](repeating: 0, count: sizeInBytes)
//
//        withUnsafeBytes(of: sourceMask) { buffer in
//            let copyCount = min(sizeInBytes, buffer.count)
//            for i in 0..<copyCount {
//                self.bytes[i] = buffer[i]
//            }
//        }
//    }
//
//    /// 从字节数组创建
//    public init(sizeInBytes: Int, initialValue: [UInt8], offset: Int) {
//        guard sizeInBytes > 0, sizeInBytes <= BitMask.maxSize else {
//            self.bytes = []
//            return
//        }
//
//        // 检查溢出
//        guard offset < sizeInBytes, (offset + initialValue.count) <= sizeInBytes else {
//            self.bytes = [] // Fail gracefully
//            return
//        }
//
//        self.bytes = [UInt8](repeating: 0, count: sizeInBytes)
//        for i in 0..<initialValue.count {
//            self.bytes[offset + i] = initialValue[i]
//        }
//    }
//
//    // MARK: - Basic Operations
//
//    public var description: String {
//        var str = "\(size):0x"
//        for byte in bytes {
//            str += String(format: "%02x", byte)
//        }
//        return str
//    }
//
//    public static func == (lhs: BitMask, rhs: BitMask) -> Bool {
//        let commonSize = min(lhs.size, rhs.size)
//
//        // 1. 比较公共部分
//        if lhs.bytes.prefix(commonSize) != rhs.bytes.prefix(commonSize) {
//            return false
//        }
//
//        // 2. 较长的部分必须全为 0
//        if lhs.size > rhs.size {
//            return lhs.bytes.suffix(from: commonSize).allSatisfy { $0 == 0 }
//        } else if rhs.size > lhs.size {
//            return rhs.bytes.suffix(from: commonSize).allSatisfy { $0 == 0 }
//        }
//
//        return true
//    }
//
//    public var isZero: Bool {
//        // 优化：使用 allSatisfy，编译器可能会进行向量化优化
//        return bytes.allSatisfy { $0 == 0 }
//    }
//
//    public var isNonZero: Bool {
//        return !isZero
//    }
//
//    public mutating func makeZero() {
//        // 保持容量，快速清零
//        let count = bytes.count
//        bytes.removeAll(keepingCapacity: true)
//        bytes.append(contentsOf: repeatElement(0, count: count))
//    }
//
//    public mutating func complement() {
//        for i in 0..<bytes.count {
//            bytes[i] = ~bytes[i]
//        }
//    }
//
//    /// 计算置位 (1) 的数量
//    public var countSetBits: Int {
//        // 优化：Swift 的 nonzeroBitCount 映射到 CPU POPCNT 指令，比 C++ 查表法更快
//        return bytes.reduce(0) { $0 + $1.nonzeroBitCount }
//    }
//
//    /// 计算零位 (0) 的数量
//    public var countZeroBits: Int {
//        return (size * 8) - countSetBits
//    }
//
//    // MARK: - Masking Operations
//
//    public mutating func andMask<T: FixedWidthInteger>(_ value: T, offset: Int) {
//        withUnsafeBytes(of: value) { buffer in
//            let byteBuffer = Array(buffer)
//            self.andMask(bytes: byteBuffer, offset: offset)
//        }
//    }
//
//    public mutating func andMask(_ other: BitMask, offset: Int) {
//        self.andMask(bytes: other.bytes, offset: offset)
//    }
//
//    private mutating func andMask(bytes otherBytes: [UInt8], offset: Int) {
//        guard offset < size else { return }
//        let commonLen = min(otherBytes.count, size - offset)
//
//        for i in 0..<commonLen {
//            bytes[offset + i] &= otherBytes[i]
//        }
//    }
//
//    public mutating func andNotMask(_ other: BitMask, offset: Int) {
//        guard offset < size else { return }
//        let commonLen = min(other.bytes.count, size - offset)
//
//        for i in 0..<commonLen {
//            bytes[offset + i] &= ~other.bytes[i]
//        }
//    }
//
//    // MARK: - Advanced Logic (The Core of Enum Layout)
//
//    /// 仅保留最高的 N 个位 (Most Significant Bits)。
//    /// 这里的 "Most Significant" 是指在整个 Mask 范围内的数值高位。
//    /// 在小端序内存中，这意味着高地址字节的高位。
//    public mutating func keepOnlyMostSignificantBits(_ n: Int) {
//        if size < 1 { return }
//
//        var count = 0
//        // 从高地址向低地址遍历 (Little Endian: High Address = High Value)
//        for i in (0..<size).reversed() {
//            if count < n {
//                var byte = bytes[i]
//                // 从字节的高位 (0x80) 向低位 (0x01) 扫描
//                var bitMask: UInt8 = 0x80
//                while bitMask > 0 {
//                    if count >= n {
//                        // 已经收集够了 N 个位，剩下的位清零
//                        byte &= ~bitMask
//                    } else if (byte & bitMask) != 0 {
//                        // 发现一个置位，计数 +1
//                        count += 1
//                    }
//                    bitMask >>= 1
//                }
//                bytes[i] = byte
//            } else {
//                // 已经收集够了，剩下的低地址字节全部清零
//                bytes[i] = 0
//            }
//        }
//    }
//
//    public mutating func keepOnlyLeastSignificantBytes(_ n: Int) {
//        if size > n {
//            bytes.removeLast(size - n)
//        }
//    }
//
//    // MARK: - Reading Logic
//
//    /// 模拟 C++ 的 readMaskedInteger。
//    /// 从内存中读取数据，只提取 Mask 中为 1 的位，并将它们压缩成一个整数。
//    /// - Parameters:
//    ///   - data: 从内存读取的原始字节数据 (必须至少与 Mask 一样大)
//    ///   - startOffset: data 中开始读取的偏移量
//    /// - Returns: 压缩后的整数
//    public func readMaskedInteger(from data: [UInt8], startOffset: Int) -> UInt64 {
//        guard (startOffset + size) <= data.count else { return 0 }
//
//        var result: UInt64 = 0
//        var resultBitShift = 0
//
//        // 遍历 Mask 的每一个字节
//        for i in 0..<size {
//            let maskByte = bytes[i]
//
//            // 优化：如果 Mask 字节为 0，直接跳过 8 位
//            if maskByte == 0 {
//                continue
//            }
//
//            let dataByte = data[startOffset + i]
//
//            // 遍历字节中的每一位 (0..7)
//            for bit in 0..<8 {
//                let bitMask = UInt8(1 << bit)
//
//                // 如果 Mask 在这一位是 1，我们需要采集数据
//                if (maskByte & bitMask) != 0 {
//                    // 如果数据在这一位也是 1
//                    if (dataByte & bitMask) != 0 {
//                        result |= (1 << resultBitShift)
//                    }
//                    // 无论数据是 0 还是 1，只要 Mask 是 1，结果的位移就要 +1
//                    // 这就是 "压缩" (Gather) 的过程
//                    resultBitShift += 1
//                }
//            }
//        }
//
//        return result
//    }
// }

//
// import Foundation
//
///// A Swift port of `Bitmask.h` from the Swift compiler.
///// Handles arbitrary-length bitmasks used for tracking spare bits in enum layouts.
// public struct BitMask: Equatable, CustomStringConvertible, Sendable {
//    private var _bytes: [UInt8]
//
//    public var size: Int { _bytes.count }
//
//    public var bytes: [UInt8] { _bytes }
//
//    // MARK: - Initializers
//
//    /// Construct a bitmask of the appropriate number of bytes, initialized to all bits set (1).
//    public init(sizeInBytes: Int) {
//        self._bytes = [UInt8](repeating: 0xFF, count: sizeInBytes)
//    }
//
//    /// Construct from raw bytes.
//    public init(bytes: [UInt8]) {
//        self._bytes = bytes
//    }
//
//    /// Construct a zero mask.
//    public static func zeroMask(sizeInBytes: Int) -> BitMask {
//        var mask = BitMask(sizeInBytes: sizeInBytes)
//        mask.makeZero()
//        return mask
//    }
//
//    // MARK: - Accessors
//
//    /// Safe read/write access to bytes.
//    public subscript(byteAt index: Int) -> UInt8 {
//        get { _bytes[index] }
//        set { _bytes[index] = newValue }
//    }
//
//    // MARK: - Manipulation
//
//    public mutating func makeZero() {
//        for i in 0..<_bytes.count { _bytes[i] = 0 }
//    }
//
//    public mutating func invert() {
//        for i in 0..<_bytes.count { _bytes[i] = ~_bytes[i] }
//    }
//
//    /// ANDs this mask with another mask.
//    public mutating func formIntersection(with other: BitMask, offset: Int = 0) {
//        guard offset < size else { return }
//        let common = min(other.size, size - offset)
//        for i in 0..<common {
//            _bytes[i + offset] &= other._bytes[i]
//        }
//    }
//
//    /// ANDs this mask with the complement of another mask.
//    public mutating func formSubtract(from other: BitMask, offset: Int = 0) {
//        guard offset < size else { return }
//        let common = min(other.size, size - offset)
//        for i in 0..<common {
//            _bytes[i + offset] &= ~other._bytes[i]
//        }
//    }
//
//    public mutating func keepOnlyLeastSignificantBytes(_ n: Int) {
//        if size > n {
//            _bytes = Array(_bytes.prefix(n))
//        }
//    }
//
//    /// Zero all bits except for the `n` most significant ones.
//    /// Scans from High Address -> Low Address, High Bit -> Low Bit.
//    /// This is the core logic for selecting Tag bits in MPEs.
//    public mutating func keepOnlyMostSignificantBits(_ n: Int) {
//        guard size > 0 else { return }
//
//        var count = 0
//        var i = size
//
//        while i > 0 {
//            i -= 1
//            if count < n {
//                var b: UInt8 = 128 // Bit 7
//                while b > 0 {
//                    if count >= n {
//                        _bytes[i] &= ~b
//                    } else if (_bytes[i] & b) != 0 {
//                        count += 1
//                    }
//                    b >>= 1
//                }
//            } else {
//                _bytes[i] = 0
//            }
//        }
//    }
//
//    // MARK: - Queries
//
//    public var isZero: Bool {
//        return !_bytes.contains { $0 != 0 }
//    }
//
//    public func countSetBits() -> Int {
//        return _bytes.reduce(0) { $0 + $1.nonzeroBitCount }
//    }
//
//    // MARK: - Scatter / Gather (PDEP / PEXT)
//
//    /// Unpack bits from the low bits of `value` and move them to the bit positions
//    /// indicated by this mask. (Used for writing Tags)
//    /// Corresponds to `irgen::emitScatterBits` / `APInt::scatterBits`.
//    public func scatterBits(value: Int) -> [UInt8] {
//        var result = [UInt8](repeating: 0, count: size)
//        var tempValue = value
//
//        // Iterate from LSB (Byte 0, Bit 0) to MSB
//        for i in 0..<size {
//            let maskByte = _bytes[i]
//            if maskByte == 0 { continue }
//
//            var b: UInt8 = 1
//            while b != 0 {
//                if (maskByte & b) != 0 {
//                    // If mask has a bit, take the next bit from value
//                    if (tempValue & 1) == 1 {
//                        result[i] |= b
//                    }
//                    tempValue >>= 1
//                }
//                if b == 128 { break }
//                b <<= 1
//            }
//        }
//        return result
//    }
//
//    /// Pack masked bits from `data` into the low bits of an integer. (Used for reading Tags)
//    /// Corresponds to `BitMask::readMaskedInteger`.
//    public func gatherBits(from data: [UInt8], offset: Int = 0) -> Int {
//        guard offset + size <= data.count else { return 0 }
//
//        var result = 0
//        var resultBit = 1
//
//        for i in 0..<size {
//            let maskByte = _bytes[i]
//            let dataByte = data[offset + i]
//
//            var b: UInt8 = 1
//            while b != 0 {
//                if (maskByte & b) != 0 {
//                    if (dataByte & b) != 0 {
//                        result |= resultBit
//                    }
//                    resultBit <<= 1
//                }
//                if b == 128 { break }
//                b <<= 1
//            }
//        }
//        return result
//    }
//
//    public var description: String {
//        return _bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
//    }
// }
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
