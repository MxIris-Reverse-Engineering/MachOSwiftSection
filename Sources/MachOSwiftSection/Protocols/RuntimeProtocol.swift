import Foundation

public protocol RuntimeProtocol {
    associatedtype StoredPointer: FixedWidthInteger
    associatedtype StoredSignedPointer: FixedWidthInteger
    associatedtype StoredSize: FixedWidthInteger
    associatedtype StoredPointerDifference: FixedWidthInteger
    associatedtype PointerSize: FixedWidthInteger
    static var pointerSize: PointerSize { get }
}
