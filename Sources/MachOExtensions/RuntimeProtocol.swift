/// Protocol defining the characteristics of a runtime target architecture.
///
/// This protocol abstracts the differences between 32-bit and 64-bit architectures,
/// as well as in-process vs external (file-based) memory access patterns.
///
/// Inspired by Swift Runtime's `RuntimeTarget` in `swift/include/swift/ABI/TargetLayout.h`.
public protocol RuntimeProtocol: Sendable {
    associatedtype StoredPointer: FixedWidthInteger & UnsignedInteger & Sendable
    associatedtype StoredSignedPointer: FixedWidthInteger & Sendable
    associatedtype StoredSize: FixedWidthInteger & UnsignedInteger & Sendable
    associatedtype StoredPointerDifference: FixedWidthInteger & SignedInteger & Sendable
    static var pointerSize: Int { get }
}

// MARK: - External Runtime Targets (for file-based reading)

/// 32-bit external runtime target for reading 32-bit MachO files.
public enum RuntimeTarget32: RuntimeProtocol {
    public typealias StoredPointer = UInt32
    public typealias StoredSignedPointer = Int32
    public typealias StoredSize = UInt32
    public typealias StoredPointerDifference = Int32
    public static var pointerSize: Int { 4 }
}

/// 64-bit external runtime target for reading 64-bit MachO files.
public enum RuntimeTarget64: RuntimeProtocol {
    public typealias StoredPointer = UInt64
    public typealias StoredSignedPointer = Int64
    public typealias StoredSize = UInt64
    public typealias StoredPointerDifference = Int64
    public static var pointerSize: Int { 8 }
}

// MARK: - InProcess Runtime Target (for direct memory access)

/// In-process runtime target for direct memory access.
///
/// This runtime uses native pointer sizes and allows direct memory operations
/// without going through file I/O. Equivalent to Swift Runtime's `InProcess` struct.
///
/// Key difference from external targets:
/// - External: `Pointer<T>` is just a `StoredPointer` (numeric value)
/// - InProcess: `Pointer<T>` can be a real `UnsafePointer<T>` for direct access
public enum InProcess: RuntimeProtocol {
    public typealias StoredPointer = UInt
    public typealias StoredSignedPointer = Int
    public typealias StoredSize = UInt
    public typealias StoredPointerDifference = Int
    public static var pointerSize: Int { MemoryLayout<UInt>.size }
}
