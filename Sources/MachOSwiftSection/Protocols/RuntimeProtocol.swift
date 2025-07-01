public protocol RuntimeProtocol {
    associatedtype StoredPointer: FixedWidthInteger
    associatedtype StoredSignedPointer: FixedWidthInteger
    associatedtype StoredSize: FixedWidthInteger
    associatedtype StoredPointerDifference: FixedWidthInteger
    static var pointerSize: Int { get }
}


public enum RuntimeTarget32: RuntimeProtocol {
    public typealias StoredPointer = UInt32
    public typealias StoredSignedPointer = UInt32
    public typealias StoredSize = UInt32
    public typealias StoredPointerDifference = Int32
    public static var pointerSize: Int { 4 }
}

public enum RuntimeTarget64: RuntimeProtocol {
    public typealias StoredPointer = UInt64
    public typealias StoredSignedPointer = Int64
    public typealias StoredSize = UInt64
    public typealias StoredPointerDifference = Int64
    public static var pointerSize: Int { 8 }
}
