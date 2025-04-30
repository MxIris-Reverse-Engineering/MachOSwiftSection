import Foundation

/// 定义了作为标志集（位域）操作所需能力的协议。
///
/// 任何遵循此协议的类型都需要提供一个底层的 `RawValue` (必须是 `FixedWidthInteger`)
/// 来存储位，并实现相应的初始化方法。
///
/// 协议扩展提供了 `getFlag`, `setFlag`, `getField`, `setField` 的默认实现，
/// 这些实现直接操作 `rawValue` 属性。
///
/// 使用方式：
/// 1. 定义一个具体的结构体，例如 `MyFlags`.
/// 2. 让这个结构体遵循 `FlagSetProtocol`.
/// 3. 指定 `RawValue` 类型 (例如 `UInt8`, `UInt16`).
/// 4. 实现协议要求的 `rawValue` 属性和 `init(rawValue:)` 初始化器。
/// 5. （可选）如果需要自定义位操作逻辑，可以覆盖协议扩展提供的默认方法。
/// 6. 在你的结构体上（或其扩展中）定义计算属性，使用协议提供的
///    `getFlag`, `setFlag`, `getField`, `setField` 方法来访问特定的位或字段。
///
/// 示例：
/// ```swift
/// struct MySettings: FlagSetProtocol {
///     typealias RawValue = UInt8
///     var rawValue: RawValue
///
///     init(rawValue: RawValue) {
///         self.rawValue = rawValue
///     }
///
///     // 定义位常量 (通常放在类型内部或相关命名空间)
///     private enum Bits {
///         static let isEnabled = 0
///         static let retryCount = 1 // 字段起始位
///         static let retryCountWidth = 3 // 字段宽度 (位 1, 2, 3)
///         static let needsSync = 4
///     }
///
///     // 单个位标志的访问器 (使用协议提供的默认实现)
///     var isEnabled: Bool {
///         get { getFlag(bit: Bits.isEnabled) }
///         set { setFlag(newValue, bit: Bits.isEnabled) }
///     }
///
///     var needsSync: Bool {
///         get { getFlag(bit: Bits.needsSync) }
///         set { setFlag(newValue, bit: Bits.needsSync) }
///     }
///
///     // 多位字段的访问器 (使用协议提供的默认实现)
///     var retryCount: UInt8 {
///         get { getField(firstBit: Bits.retryCount, bitWidth: Bits.retryCountWidth) }
///         set { setField(newValue, firstBit: Bits.retryCount, bitWidth: Bits.retryCountWidth) }
///     }
/// }
///
/// var settings = MySettings(rawValue: 0b0001_0110) // retryCount=3, isEnabled=false, needsSync=true
/// print(settings.isEnabled)    // false
/// print(settings.retryCount) // 3
/// print(settings.needsSync)    // true
/// settings.isEnabled = true
/// settings.retryCount = 5
/// print(settings.rawValue)     // 0b0001_1011 (27) -> retryCount=5, isEnabled=true, needsSync=true
///
/// let settings2 = MySettings(rawValue: 0b0001_1011)
/// print(settings == settings2) // true (Equatable 来自协议扩展)
/// ```
public protocol FlagSet: Equatable { // 添加 Equatable 约束，通常标志集需要比较
    /// 用于存储标志位的底层整数类型。
    associatedtype RawValue: FixedWidthInteger

    /// 底层的整数值，存储着所有的标志位和字段。
    /// conforming 类型必须提供这个属性的存储和访问。
    var rawValue: RawValue { get set }

    /// 使用给定的原始整数值初始化。
    /// conforming 类型必须实现这个初始化器。
    init(rawValue: RawValue)

    // MARK: - Flag and Field Accessors (Protocol Requirements)

    // 这些方法在协议中声明，以便 conforming 类型可以选择性地提供自定义实现。
    // 默认实现由下面的协议扩展提供。

    /// 读取单个位标志。
    func flag(bit: Int) -> Bool

    /// 设置单个位标志。
    mutating func setFlag(_ value: Bool, bit: Int)

    /// 读取一个多位字段的值，返回指定类型。
    func field<FieldType: FixedWidthInteger>(
        firstBit: Int,
        bitWidth: Int,
        fieldType: FieldType.Type
    ) -> FieldType where FieldType.Magnitude == FieldType // Common constraint

    /// 给一个多位字段赋值。
    mutating func setField<FieldType: FixedWidthInteger>(
        _ value: FieldType,
        firstBit: Int,
        bitWidth: Int
    )
}

// MARK: - Default Implementations

extension FlagSet {
    // MARK: - Helper Functions for Masks (Static within Extension)

    /// 为给定位宽创建一个低位掩码。
    @inline(__always)
    private static func lowMask(forBitWidth bitWidth: Int) -> RawValue {
        precondition(bitWidth >= 0 && bitWidth <= RawValue.bitWidth, "Bit width must be between 0 and the storage type's bit width.")
        if bitWidth == RawValue.bitWidth {
            return ~RawValue(0) // All bits set
        }
        if bitWidth == 0 {
            return 0
        }
        let mask = (RawValue(1) << bitWidth) &- 1
        return mask
    }

    /// 为指定位范围创建掩码。
    @inline(__always)
    private static func mask(forFirstBit firstBit: Int, bitWidth: Int = 1) -> RawValue {
        precondition(firstBit >= 0, "First bit index cannot be negative.")
        precondition(bitWidth >= 1, "Bit width must be at least 1.")
        precondition(firstBit + bitWidth <= RawValue.bitWidth, "Field extends beyond the storage type's bit width.")
        return lowMask(forBitWidth: bitWidth) << firstBit
    }

    // MARK: - Default Flag and Field Accessor Implementations

    @inline(__always)
    public func flag(bit: Int) -> Bool {
        precondition(bit >= 0 && bit < RawValue.bitWidth, "Bit index out of range.")
        // 使用 Self.maskFor 访问静态辅助函数
        return (rawValue & Self.mask(forFirstBit: bit)) != 0
    }

    @inline(__always)
    public mutating func setFlag(_ value: Bool, bit: Int) {
        precondition(bit >= 0 && bit < RawValue.bitWidth, "Bit index out of range.")
        let mask = Self.mask(forFirstBit: bit)
        if value {
            rawValue |= mask
        } else {
            rawValue &= ~mask
        }
    }

    @inline(__always)
    public func field<FieldType: FixedWidthInteger>(
        firstBit: Int,
        bitWidth: Int,
        fieldType: FieldType.Type = FieldType.self // Default to inferring or specified type
    ) -> FieldType where FieldType.Magnitude == FieldType {
        precondition(bitWidth > 0, "Bit width must be positive.")
        precondition(firstBit >= 0 && (firstBit + bitWidth) <= RawValue.bitWidth, "Field range is out of bounds for the storage type.")
        precondition(FieldType.bitWidth >= bitWidth, "The requested FieldType is too small to represent a value of the specified bitWidth.")

        let mask = Self.lowMask(forBitWidth: bitWidth)
        let shiftedValue = rawValue >> firstBit
        let isolatedValue = shiftedValue & mask
        return FieldType(truncatingIfNeeded: isolatedValue)
    }

    @inline(__always)
    public mutating func setField<FieldType: FixedWidthInteger>(
        _ value: FieldType,
        firstBit: Int,
        bitWidth: Int
    ) {
        precondition(bitWidth > 0, "Bit width must be positive.")
        precondition(firstBit >= 0 && (firstBit + bitWidth) <= RawValue.bitWidth, "Field range is out of bounds for the storage type.")

        let valueMask = Self.lowMask(forBitWidth: bitWidth)
        let rawValueEquivalent = RawValue(truncatingIfNeeded: value)

        precondition((rawValueEquivalent & ~valueMask) == 0, "Value \(value) is too large to fit in a field of width \(bitWidth).")

        let fieldMask = Self.mask(forFirstBit: firstBit, bitWidth: bitWidth)
        rawValue &= ~fieldMask
        rawValue |= (rawValueEquivalent << firstBit) & fieldMask
    }

    // MARK: - Default Equatable Conformance

    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}


